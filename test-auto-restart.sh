#!/bin/bash
# Tests for root/auto-restart.sh restart and give-up behaviour.
#
# Drives monitor_once() against a stub health check whose tunnel state the
# test controls, with sleeps, process control and the s6 halt stubbed out.
# Needs GNU-style stat, timeout and jq, so run it inside the image:
#
#   docker run --rm --entrypoint bash -v "$PWD:/src:ro" magicalyak/nzbgetvpn:<tag> /src/test-auto-restart.sh

set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSED=0
FAILED=0

ok()   { echo "  ok   $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL $1"; FAILED=$((FAILED + 1)); }
expect() { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1: got '$2' want '$3'"; fi; }

# Fresh sandbox and a freshly sourced script for each scenario
setup() {
    T=$(mktemp -d)
    export AUTO_RESTART_STATE_DIR="$T"
    export STATUS_FILE="$T/status.json"
    export RESTART_LOG="$T/auto-restart.log"
    export S6_EXITCODE_FILE="$T/exitcode"
    export S6_HALT="$T/halt"
    export HEALTHCHECK_SCRIPT="$T/healthcheck"
    export VPN_SETUP_SCRIPT="$T/vpn-setup"
    export ENABLE_AUTO_RESTART=true
    export MAX_RESTART_ATTEMPTS=3
    export RESTART_COOLDOWN_SECONDS=0
    export RESTART_FAILURE_THRESHOLD=3
    export HEALTHY_CHECKS_BEFORE_RESET=5
    export EXIT_ON_MAX_RESTARTS=true
    export NOTIFICATION_WEBHOOK_URL=
    export VPN_SETUP_FLAG="$T/vpn_setup_complete"
    export AUTO_RESTART_STARTUP_GRACE=0
    export AUTO_RESTART_SETUP_TIMEOUT=600
    touch "$VPN_SETUP_FLAG"

    printf '#!/bin/sh\necho halted >> %s/halt.calls\n' "$T" > "$S6_HALT"
    printf '#!/bin/sh\nexit 0\n' > "$VPN_SETUP_SCRIPT"
    # Stub health check: reports whatever $T/tunnel says, with a new
    # timestamp every run, like the real script does
    cat > "$HEALTHCHECK_SCRIPT" <<STUB
#!/bin/bash
seq=\$(( \$(cat $T/seq 2>/dev/null || echo 0) + 1 )); echo \$seq > $T/seq
case "\$(cat $T/tunnel)" in
  ok)   iface=up;      conn=success; overall=healthy ;;
  dead) iface=up;      conn=failed;  overall=degraded ;;
  gone) iface=missing; conn=failed;  overall=unhealthy ;;
esac
cat > $STATUS_FILE <<JSON
{"timestamp": "run-\$seq", "status": "\$overall",
 "checks": {"nzbget": "success", "vpn_interface": "\$iface", "vpn_connectivity": "\$conn"}}
JSON
STUB
    chmod +x "$S6_HALT" "$VPN_SETUP_SCRIPT" "$HEALTHCHECK_SCRIPT"

    # shellcheck source=root/auto-restart.sh
    source "$SRC_DIR/root/auto-restart.sh"
    set +e
    sleep() { :; }
    pgrep() { return 1; }
    pkill() { :; }
    s6-svc() { :; }
}

teardown() { rm -rf "$T"; }

tunnel() { echo "$1" > "$T/tunnel"; }

# One monitoring pass after the monitoring server's probe has run once
pass() { "$HEALTHCHECK_SCRIPT"; monitor_once; }

vpn_restarts() { get_restart_count "$VPN_RESTART_COUNT_FILE"; }

echo "A single failed probe does not restart the tunnel"
setup
tunnel ok;   pass; pass
tunnel dead; pass
tunnel ok;   pass
expect "no restart after one failure" "$(vpn_restarts)" 0
teardown

echo
echo "Interface up but no traffic is treated as a VPN failure"
setup
tunnel dead; pass; pass; pass
expect "restart attempted after 3 consecutive failures" "$(vpn_restarts)" 1
teardown

echo
echo "Missing interface is treated as a VPN failure"
setup
tunnel gone; pass; pass; pass
expect "restart attempted" "$(vpn_restarts)" 1
teardown

echo
echo "Re-reading the same status does not count as a new observation"
setup
tunnel dead; "$HEALTHCHECK_SCRIPT"
monitor_once; monitor_once; monitor_once; monitor_once
expect "one stale status is one failure, not four" "$vpn_fail_streak" 1
expect "no restart" "$(vpn_restarts)" 0
teardown

echo
echo "One good check between flaps does not reset the counter"
setup
tunnel dead; pass; pass; pass
expect "first restart" "$(vpn_restarts)" 1
tunnel ok;   pass
tunnel dead; pass; pass; pass
expect "counter carried over the single good check" "$(vpn_restarts)" 2
teardown

echo
echo "Sustained health resets the counter"
setup
tunnel dead; pass; pass; pass
tunnel ok;   pass; pass; pass; pass
expect "not reset after 4 healthy checks" "$(vpn_restarts)" 1
pass
expect "reset after 5 healthy checks" "$(vpn_restarts)" 0
teardown

echo
echo "Exhausting restarts on a tunnel that stays dead exits the container"
setup
tunnel dead
(
    for _ in $(seq 1 20); do pass; done
    exit 0
)
rc=$?
expect "watchdog exits with code 1" "$rc" 1
expect "s6 exit code file holds 1" "$(cat "$T/exitcode" 2>/dev/null)" 1
expect "s6 halt invoked once" "$(wc -l < "$T/halt.calls" 2>/dev/null | tr -d ' ')" 1
expect "exactly MAX_RESTART_ATTEMPTS restarts before exiting" \
    "$(grep -c 'Restarting VPN (attempt' "$RESTART_LOG")" 3
teardown

echo
echo "A flapping tunnel also runs out of attempts and exits"
setup
(
    for _ in $(seq 1 6); do
        tunnel dead; pass; pass; pass
        tunnel ok;   pass
    done
    exit 0
)
expect "watchdog exits with code 1" "$?" 1
expect "s6 exit code file holds 1" "$(cat "$T/exitcode" 2>/dev/null)" 1
teardown

echo
echo "EXIT_ON_MAX_RESTARTS=false keeps the container running"
setup
export EXIT_ON_MAX_RESTARTS=false
EXIT_ON_MAX_RESTARTS=false
tunnel dead
(
    for _ in $(seq 1 20); do pass; done
    exit 0
)
expect "watchdog keeps running" "$?" 0
expect "halt not invoked" "$([[ -f $T/halt.calls ]] && echo yes || echo no)" no
expect "gave-up message logged once" "$(grep -c 'no further VPN restarts' "$RESTART_LOG")" 1
teardown

echo
echo "Failures during the startup grace period are not counted"
setup
AUTO_RESTART_STARTUP_GRACE=120
tunnel gone; pass; pass; pass; pass
expect "no failures counted" "$vpn_fail_streak" 0
expect "no restart" "$(vpn_restarts)" 0
expect "no failure logged" "$(grep -c 'failure detected' "$RESTART_LOG")" 0
expect "waiting message logged once" "$(grep -c 'Waiting for VPN setup' "$RESTART_LOG")" 1
AUTO_RESTART_STARTUP_GRACE=0
pass
expect "counted once the grace period is over" "$vpn_fail_streak" 1
teardown

echo
echo "Failures are not counted before VPN setup completes"
setup
rm -f "$VPN_SETUP_FLAG"
tunnel gone; pass; pass; pass
expect "no failures counted" "$vpn_fail_streak" 0
touch "$VPN_SETUP_FLAG"
pass
expect "counted once setup is done" "$vpn_fail_streak" 1
teardown

echo
echo "A setup that never completes does not idle the watchdog forever"
setup
rm -f "$VPN_SETUP_FLAG"
tunnel gone; pass
expect "not counted before the setup timeout" "$vpn_fail_streak" 0
watchdog_started_at=$(( $(date +%s) - 601 ))
pass
expect "counted after the setup timeout" "$vpn_fail_streak" 1
expect "timeout logged" "$(grep -c 'has not completed after' "$RESTART_LOG")" 1
teardown

echo
echo "================================================"
echo "passed=$PASSED failed=$FAILED"
[[ $FAILED -eq 0 ]]
