#!/bin/bash
# Docker HEALTHCHECK entry point. The monitoring server already runs
# healthcheck.sh every HEALTH_CHECK_INTERVAL seconds and caches the result in
# the status file, so report that result instead of probing a second time.
# Falls back to a full run when the file is missing, unreadable or older than
# HEALTHCHECK_CACHE_MAX_AGE seconds (for example with ENABLE_MONITORING=no).

STATUS_FILE=${STATUS_FILE:-/tmp/nzbgetvpn_status.json}
HEALTHCHECK_SCRIPT=${HEALTHCHECK_SCRIPT:-/root/healthcheck.sh}
HEALTHCHECK_CACHE_MAX_AGE=${HEALTHCHECK_CACHE_MAX_AGE:-90}

if mtime=$(stat -c %Y "$STATUS_FILE" 2>/dev/null) \
    && (( $(date +%s) - mtime <= HEALTHCHECK_CACHE_MAX_AGE )) \
    && code=$(jq -er '.exit_code | select(type == "number")' "$STATUS_FILE" 2>/dev/null); then
    exit "$code"
fi

exec "$HEALTHCHECK_SCRIPT"
