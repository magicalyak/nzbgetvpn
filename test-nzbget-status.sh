#!/bin/bash
# Tests for the nzbgetvpn_nzbget_* series against a real NZBGet: each one is
# checked in the state it exists to catch (paused, config error at start, API
# down) and again after that state clears. Needs the image's NZBGet, so run it
# inside the image:
#
#   docker run --rm --entrypoint bash -v "$PWD:/src:ro" magicalyak/nzbgetvpn:<tag> /src/test-nzbget-status.sh

set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSED=0
FAILED=0

ok()   { echo "  ok   $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL $1"; FAILED=$((FAILED + 1)); }
expect() { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1: got '$2' want '$3'"; fi; }

NZBGET=/app/nzbget/nzbget
RPC=http://127.0.0.1:6789/jsonrpc
PORT=18080
T=$(mktemp -d)
CONF="$T/nzbget.conf"
SERVER_PID=""

cleanup() {
    "$NZBGET" -c "$CONF" -Q >/dev/null 2>&1
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null
    sleep 1  # NZBGet is still writing its queue directory while it shuts down
    rm -rf "$T" 2>/dev/null
}
trap cleanup EXIT

sed -e "s|^MainDir=.*|MainDir=$T/main|" \
    -e 's|^DestDir=.*|DestDir=${MainDir}/completed|' \
    -e 's|^InterDir=.*|InterDir=${MainDir}/intermediate|' \
    /app/nzbget/share/nzbget/nzbget.conf > "$CONF"
mkdir -p "$T/main"

rpc() { curl -s --max-time 5 "$RPC" -d "{\"method\":\"$1\",\"params\":[${2:-}]}"; }
api_up() { rpc version | grep -q '"result"'; }

wait_for() {  # wait_for <yes|no> <command...>: poll until the command's success matches
    local want=$1 i; shift
    for i in $(seq 1 50); do
        if "$@" >/dev/null 2>&1; then [[ $want == yes ]] && return 0; else [[ $want == no ]] && return 0; fi
        sleep 0.2
    done
    return 1
}

start_nzbget() { "$NZBGET" -D -c "$CONF" "$@" >/dev/null 2>&1; wait_for yes api_up || fail "NZBGet did not start"; }
stop_nzbget()  { "$NZBGET" -c "$CONF" -Q >/dev/null 2>&1; wait_for no api_up || fail "NZBGet did not stop"; }

# Value of one series from a fresh scrape, or "absent"
metric() {
    curl -s --max-time 10 "http://127.0.0.1:$PORT/metrics" | awk -v n="nzbgetvpn_nzbget_$1" '$1 == n {print $2; found=1} END {if (!found) print "absent"}'
}

MONITORING_PORT=$PORT ENABLE_HEALTH_PROBE=false NZBGET_CONF="$CONF" STATUS_FILE="$T/status.json" \
    python3 "$SRC_DIR/root/monitoring-server.py" >"$T/server.log" 2>&1 &
SERVER_PID=$!
wait_for yes curl -sf "http://127.0.0.1:$PORT/metrics" || { fail "monitoring server did not start"; cat "$T/server.log"; }

echo "NZBGet not running: series are absent, not 0"
expect "other metrics still served" "$(curl -s "http://127.0.0.1:$PORT/metrics" | grep -c '^nzbgetvpn_healthy ')" 1
for name in download_paused post_paused scan_paused download_rate_bytes remaining_bytes server_standby config_error; do
    expect "$name absent" "$(metric $name)" absent
done

echo
echo "Clean start, empty queue"
start_nzbget
expect "download_paused" "$(metric download_paused)" 0
expect "post_paused" "$(metric post_paused)" 0
expect "scan_paused" "$(metric scan_paused)" 0
expect "download_rate_bytes" "$(metric download_rate_bytes)" 0
expect "remaining_bytes" "$(metric remaining_bytes)" 0
expect "server_standby" "$(metric server_standby)" 1
expect "config_error" "$(metric config_error)" 0

echo
echo "Pause and resume each activity over JSON-RPC"
rpc pausedownload >/dev/null
expect "download_paused after pausedownload" "$(metric download_paused)" 1
expect "post_paused untouched" "$(metric post_paused)" 0
rpc resumedownload >/dev/null
expect "download_paused after resumedownload" "$(metric download_paused)" 0
rpc pausepost >/dev/null
expect "post_paused after pausepost" "$(metric post_paused)" 1
rpc resumepost >/dev/null
expect "post_paused after resumepost" "$(metric post_paused)" 0
rpc pausescan >/dev/null
expect "scan_paused after pausescan" "$(metric scan_paused)" 1
rpc resumescan >/dev/null
expect "scan_paused after resumescan" "$(metric scan_paused)" 0

echo
echo "Paused with a queue: the state the alert is for"
rpc pausedownload >/dev/null
NZB='<?xml version="1.0" encoding="UTF-8"?><nzb xmlns="http://www.newzbin.com/DTD/2003/nzb"><file poster="t@example.com" date="1790000000" subject="test.bin (1/1)"><groups><group>alt.binaries.test</group></groups><segments><segment bytes="5000000" number="1">test-segment-1@example.com</segment></segments></file></nzb>'
rpc append "\"test.nzb\",\"$(printf '%s' "$NZB" | base64 | tr -d '\n')\",\"\",0,false,false,\"\",0,\"SCORE\",[]" >/dev/null
remaining_positive() { [[ "$(metric remaining_bytes)" =~ ^[1-9][0-9]*$ ]]; }
wait_for yes remaining_positive
expect "remaining_bytes counts the queued nzb" "$(metric remaining_bytes)" 5000000
expect "download_paused" "$(metric download_paused)" 1

echo
echo "Restart with a config error: NZBGet pauses everything itself"
stop_nzbget
for name in download_paused remaining_bytes; do
    expect "$name absent while NZBGet is down" "$(metric $name)" absent
done
expect "config_error still read from the log while NZBGet is down" "$(metric config_error)" 0
start_nzbget -o DestDir=/proc/version/completed
expect "download_paused" "$(metric download_paused)" 1
expect "post_paused" "$(metric post_paused)" 1
expect "scan_paused" "$(metric scan_paused)" 1
expect "config_error" "$(metric config_error)" 1
expect "remaining_bytes survives the restart" "$(metric remaining_bytes)" 5000000
rpc resumedownload >/dev/null; rpc resumepost >/dev/null; rpc resumescan >/dev/null
# No news servers are configured, so the resumed download fails and the queue may drain
expect "download_paused after a manual resume" "$(metric download_paused)" 0
expect "config_error stays 1 until the next start" "$(metric config_error)" 1

echo
echo "Clean restart clears the config error"
stop_nzbget
start_nzbget
expect "config_error" "$(metric config_error)" 0
expect "download_paused" "$(metric download_paused)" 0

echo
echo "================================================"
echo "passed=$PASSED failed=$FAILED"
[[ $FAILED -eq 0 ]]
