#!/bin/bash
# Tests for root/healthcheck-cached.sh, the Docker HEALTHCHECK entry point.
# Needs GNU-style stat and jq, so run it inside the image:
#
#   docker run --rm --entrypoint bash -v "$PWD:/src:ro" magicalyak/nzbgetvpn:<tag> /src/test-healthcheck-cached.sh

set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSED=0
FAILED=0

ok()   { echo "  ok   $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL $1"; FAILED=$((FAILED + 1)); }
expect() { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1: got '$2' want '$3'"; fi; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export STATUS_FILE="$T/status.json"
export HEALTHCHECK_SCRIPT="$T/healthcheck"
export HEALTHCHECK_CACHE_MAX_AGE=90
# Stub full check: records that it ran and exits 42
printf '#!/bin/sh\necho ran >> %s/full.calls\nexit 42\n' "$T" > "$HEALTHCHECK_SCRIPT"
chmod +x "$HEALTHCHECK_SCRIPT"

run() { rm -f "$T/full.calls"; "$SRC_DIR/root/healthcheck-cached.sh"; echo $?; }
full_ran() { [[ -f "$T/full.calls" ]] && echo yes || echo no; }

echo "Fresh status file is reported without a second probe"
echo '{"status": "healthy", "exit_code": 0}' > "$STATUS_FILE"
expect "exit code from cache" "$(run)" 0
expect "full check not run" "$(full_ran)" no
echo '{"status": "degraded", "exit_code": 4}' > "$STATUS_FILE"
expect "failing exit code from cache" "$(run)" 4
expect "full check not run" "$(full_ran)" no

echo
echo "Stale status file falls back to a full run"
touch -d "@$(( $(date +%s) - 120 ))" "$STATUS_FILE"
expect "exit code from full run" "$(run)" 42
expect "full check ran" "$(full_ran)" yes

echo
echo "Missing status file falls back to a full run"
rm -f "$STATUS_FILE"
expect "exit code from full run" "$(run)" 42
expect "full check ran" "$(full_ran)" yes

echo
echo "Unreadable status file falls back to a full run"
echo 'not json' > "$STATUS_FILE"
expect "exit code from full run" "$(run)" 42
echo '{"status": "healthy"}' > "$STATUS_FILE"
expect "missing exit_code falls back" "$(run)" 42

echo
echo "================================================"
echo "passed=$PASSED failed=$FAILED"
[[ $FAILED -eq 0 ]]
