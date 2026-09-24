#!/bin/bash

# Auto-restart script for nzbgetvpn
# Monitors health status and automatically restarts failed services. When a
# service still fails after MAX_RESTART_ATTEMPTS restarts, the whole container
# exits non-zero (EXIT_ON_MAX_RESTARTS=true) so Docker or Kubernetes replaces
# it, instead of the watchdog giving up and leaving a dead tunnel in place.

set -euo pipefail

# Configuration
RESTART_LOG=${RESTART_LOG:-/config/auto-restart.log}
STATUS_FILE=${STATUS_FILE:-/tmp/nzbgetvpn_status.json}
HEALTHCHECK_SCRIPT=${HEALTHCHECK_SCRIPT:-/root/healthcheck.sh}
VPN_SETUP_SCRIPT=${VPN_SETUP_SCRIPT:-/etc/cont-init.d/50-vpn-setup}
RESTART_COOLDOWN_SECONDS=${RESTART_COOLDOWN_SECONDS:-300}  # 5 minutes
MAX_RESTART_ATTEMPTS=${MAX_RESTART_ATTEMPTS:-3}
ENABLE_AUTO_RESTART=${ENABLE_AUTO_RESTART:-false}
RESTART_ON_VPN_FAILURE=${RESTART_ON_VPN_FAILURE:-true}
RESTART_ON_NZBGET_FAILURE=${RESTART_ON_NZBGET_FAILURE:-true}
# Exit the container once MAX_RESTART_ATTEMPTS is exhausted
EXIT_ON_MAX_RESTARTS=${EXIT_ON_MAX_RESTARTS:-true}
AUTO_RESTART_CHECK_INTERVAL=${AUTO_RESTART_CHECK_INTERVAL:-30}
# Consecutive failed health checks before a restart, so one dropped probe
# does not bounce the tunnel
RESTART_FAILURE_THRESHOLD=${RESTART_FAILURE_THRESHOLD:-3}
# Consecutive passing health checks before a service's restart counter resets,
# so a tunnel that flaps up for one check between failures still runs out of
# attempts
HEALTHY_CHECKS_BEFORE_RESET=${HEALTHY_CHECKS_BEFORE_RESET:-5}
# A status file older than this is refreshed by running the health check here
HEALTH_STATUS_MAX_AGE=${HEALTH_STATUS_MAX_AGE:-180}
# Failures are not counted until VPN setup has finished and this many seconds
# have passed since, so the first checks after boot do not see a tunnel and
# NZBGet that are still coming up
AUTO_RESTART_STARTUP_GRACE=${AUTO_RESTART_STARTUP_GRACE:-120}
VPN_SETUP_FLAG=${VPN_SETUP_FLAG:-/tmp/vpn_setup_complete}
# Start counting anyway if setup has not finished after this long, so a setup
# that never completes cannot keep the watchdog idle forever
AUTO_RESTART_SETUP_TIMEOUT=${AUTO_RESTART_SETUP_TIMEOUT:-600}
# How long a VPN restart has to pass traffic again before it counts as failed
VPN_RESTART_VERIFY_TIMEOUT=${VPN_RESTART_VERIFY_TIMEOUT:-60}

# s6-overlay v3: the container exits with the code in this file once halt runs
S6_EXITCODE_FILE=${S6_EXITCODE_FILE:-/run/s6-linux-init-container-results/exitcode}
S6_HALT=${S6_HALT:-/run/s6/basedir/bin/halt}

# State files
STATE_DIR=${AUTO_RESTART_STATE_DIR:-/tmp}
LAST_VPN_RESTART_FILE="$STATE_DIR/last_vpn_restart"
LAST_NZBGET_RESTART_FILE="$STATE_DIR/last_nzbget_restart"
VPN_RESTART_COUNT_FILE="$STATE_DIR/vpn_restart_count"
NZBGET_RESTART_COUNT_FILE="$STATE_DIR/nzbget_restart_count"

# Loop state
last_status_timestamp=""
vpn_fail_streak=0
vpn_ok_streak=0
nzbget_fail_streak=0
nzbget_ok_streak=0
gave_up_vpn=false
gave_up_nzbget=false
watchdog_started_at=$(date +%s)
startup_done=false
startup_wait_logged=false

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$RESTART_LOG"
}

# Check if we're in cooldown period
check_cooldown() {
    local last_restart_file="$1"
    local current_time=$(date +%s)

    if [[ -f "$last_restart_file" ]]; then
        local last_restart=$(cat "$last_restart_file")
        local time_diff=$((current_time - last_restart))

        if [[ $time_diff -lt $RESTART_COOLDOWN_SECONDS ]]; then
            return 1  # Still in cooldown
        fi
    fi

    return 0  # Can restart
}

get_restart_count() {
    local count_file="$1"
    if [[ -f "$count_file" ]]; then
        cat "$count_file"
    else
        echo 0
    fi
}

# Update restart count
update_restart_count() {
    local count_file="$1"
    local current_count
    current_count=$(get_restart_count "$count_file")
    current_count=$((current_count + 1))
    echo "$current_count" > "$count_file"

    echo "$current_count"
}

# Reset restart count (call when service is healthy for a while)
reset_restart_count() {
    local count_file="$1"
    echo "0" > "$count_file"
}

# Run the health check here when nothing else has written a recent status
# (for example ENABLE_MONITORING=no, which also stops the monitoring server's
# probe loop).
refresh_status_if_stale() {
    local now mtime
    now=$(date +%s)
    mtime=$(stat -c %Y "$STATUS_FILE" 2>/dev/null || echo 0)
    if (( now - mtime > HEALTH_STATUS_MAX_AGE )); then
        run_healthcheck
    fi
}

run_healthcheck() {
    timeout 120 "$HEALTHCHECK_SCRIPT" >/dev/null 2>&1 || true
}

# Check current health status
get_health_status() {
    if [[ ! -f "$STATUS_FILE" ]]; then
        echo "unknown"
        return 1
    fi

    local status=$(jq -r '.status // "unknown"' "$STATUS_FILE" 2>/dev/null || echo "unknown")
    echo "$status"
}

# Get specific check status
get_check_status() {
    local check_name="$1"

    if [[ ! -f "$STATUS_FILE" ]]; then
        echo "unknown"
        return 1
    fi

    local status=$(jq -r ".checks.${check_name} // \"unknown\"" "$STATUS_FILE" 2>/dev/null || echo "unknown")
    echo "$status"
}

# The tunnel has failed if the interface is gone or down, or if traffic does
# not pass through it. An interface that exists but carries nothing is the
# failure mode that matters most, so connectivity is checked, not just the
# interface.
vpn_failed() {
    local iface conn
    iface=$(get_check_status "vpn_interface" || true)
    conn=$(get_check_status "vpn_connectivity" || true)
    case "$iface" in down|missing|failed) return 0 ;; esac
    [[ "$conn" == "failed" ]]
}

vpn_ok() {
    local iface conn
    iface=$(get_check_status "vpn_interface" || true)
    conn=$(get_check_status "vpn_connectivity" || true)
    [[ "$iface" == "up" ]] && [[ "$conn" == "success" || "$conn" == "skipped" ]]
}

# Stop the whole container with a non-zero code so the orchestrator
# replaces it. Restarting a single s6 service would keep the same /tmp
# counter files and the same stuck state, so it is not enough.
exit_container() {
    local code="${1:-1}"
    if [[ -x "$S6_HALT" ]]; then
        echo "$code" > "$S6_EXITCODE_FILE"
        "$S6_HALT"
    else
        log "ERROR" "s6 halt not found at $S6_HALT, signalling PID 1 instead"
        kill -TERM 1
    fi
    exit "$code"
}

# Called when a service has used all of its restart attempts
give_up() {
    local service="$1"
    log "ERROR" "Maximum $service restart attempts ($MAX_RESTART_ATTEMPTS) exceeded"

    if [[ "$EXIT_ON_MAX_RESTARTS" == "true" ]]; then
        log "ERROR" "Exiting container with code 1 so it is restarted (EXIT_ON_MAX_RESTARTS=true)"
        send_notification "container_exit" "$service still failing after $MAX_RESTART_ATTEMPTS restarts, exiting container"
        exit_container 1
    fi

    local already_logged=false
    case "$service" in
        VPN)    [[ "$gave_up_vpn" == "true" ]] && already_logged=true; gave_up_vpn=true ;;
        NZBGet) [[ "$gave_up_nzbget" == "true" ]] && already_logged=true; gave_up_nzbget=true ;;
    esac
    if [[ "$already_logged" != "true" ]]; then
        log "ERROR" "EXIT_ON_MAX_RESTARTS=false: no further $service restarts until it has been healthy for $HEALTHY_CHECKS_BEFORE_RESET consecutive checks"
    fi
}

# Restart VPN service
restart_vpn() {
    log "WARNING" "Attempting to restart VPN service"

    # Check cooldown
    if ! check_cooldown "$LAST_VPN_RESTART_FILE"; then
        log "INFO" "VPN restart in cooldown period, skipping"
        return 1
    fi

    # Check restart count
    local restart_count=$(update_restart_count "$VPN_RESTART_COUNT_FILE")
    if [[ $restart_count -gt $MAX_RESTART_ATTEMPTS ]]; then
        give_up "VPN"
        return 1
    fi

    log "INFO" "Restarting VPN (attempt $restart_count/$MAX_RESTART_ATTEMPTS)"

    # Update last restart time
    date +%s > "$LAST_VPN_RESTART_FILE"

    # Try to restart VPN processes
    local restart_success=false

    # The OpenVPN service starts the client as soon as this flag exists, and s6
    # respawns it the moment it is killed below. Without the flag it waits for
    # the setup rerun to finish the kill switch.
    rm -f "$VPN_SETUP_FLAG"

    # Kill existing VPN processes
    if pgrep openvpn >/dev/null 2>&1; then
        log "INFO" "Stopping OpenVPN processes"
        pkill -TERM openvpn || true
        sleep 2
        pkill -KILL openvpn || true
    fi

    if pgrep wg-quick >/dev/null 2>&1; then
        log "INFO" "Stopping WireGuard processes"
        pkill -TERM wg-quick || true
        sleep 2
    fi

    # Give time for cleanup
    sleep 5

    # Re-run VPN setup script
    if [[ -f "$VPN_SETUP_SCRIPT" ]]; then
        log "INFO" "Re-running VPN setup script"
        if bash "$VPN_SETUP_SCRIPT"; then
            restart_success=true
            log "INFO" "VPN restart completed successfully"
        else
            log "ERROR" "VPN setup script failed"
        fi
    else
        log "ERROR" "VPN setup script not found"
    fi

    if $restart_success; then
        # OpenVPN only starts once setup has finished, so give it time to connect.
        # Probe again rather than trusting an old status file.
        local waited=0
        while (( waited < VPN_RESTART_VERIFY_TIMEOUT )); do
            sleep 10
            waited=$((waited + 10))
            run_healthcheck
            if vpn_ok; then
                log "INFO" "VPN restart verification successful after ${waited}s"
                return 0
            fi
        done
        log "WARNING" "VPN restart verification failed - tunnel not passing traffic after ${waited}s"
        return 1
    else
        return 1
    fi
}

nzbget_service_dir() {
    local dir
    for dir in /run/service/svc-nzbget /run/service/nzbget /var/run/s6/services/nzbget; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}

# Restart NZBGet service
restart_nzbget() {
    log "WARNING" "Attempting to restart NZBGet service"

    # Check cooldown
    if ! check_cooldown "$LAST_NZBGET_RESTART_FILE"; then
        log "INFO" "NZBGet restart in cooldown period, skipping"
        return 1
    fi

    # Check restart count
    local restart_count=$(update_restart_count "$NZBGET_RESTART_COUNT_FILE")
    if [[ $restart_count -gt $MAX_RESTART_ATTEMPTS ]]; then
        give_up "NZBGet"
        return 1
    fi

    log "INFO" "Restarting NZBGet (attempt $restart_count/$MAX_RESTART_ATTEMPTS)"

    # Update last restart time
    date +%s > "$LAST_NZBGET_RESTART_FILE"

    local service_dir
    if service_dir=$(nzbget_service_dir); then
        # s6 stops and restarts it with the base image's user and arguments
        log "INFO" "Restarting NZBGet via s6 ($service_dir)"
        s6-svc -r "$service_dir" || true
        sleep 5
    else
        log "ERROR" "NZBGet s6 service directory not found, cannot restart NZBGet"
        return 1
    fi

    # Wait, then probe again rather than trusting an old status file
    sleep 10
    run_healthcheck
    local nzbget_status=$(get_check_status "nzbget" || true)
    if [[ "$nzbget_status" == "success" ]]; then
        log "INFO" "NZBGet restart verification successful"
        return 0
    else
        log "WARNING" "NZBGet restart verification failed - service not responding"
        return 1
    fi
}

# Send notification webhook (if configured)
send_notification() {
    local event="$1"
    local message="$2"
    local webhook_url="${NOTIFICATION_WEBHOOK_URL:-}"

    if [[ -z "$webhook_url" ]]; then
        return 0
    fi

    local payload="{\"event\":\"$event\",\"message\":\"$message\",\"timestamp\":\"$(date -Iseconds)\",\"container\":\"nzbgetvpn\"}"

    if command -v curl >/dev/null 2>&1; then
        curl -X POST \
             -H "Content-Type: application/json" \
             -d "$payload" \
             --max-time 10 \
             --silent \
             "$webhook_url" || true
    fi
}

# Returns 0 once the startup grace period is over. Setup finishing is taken
# from the flag file vpn-setup.sh touches at the end, and the grace runs from
# that file's mtime.
startup_complete() {
    [[ "$startup_done" == "true" ]] && return 0

    local now flag_mtime
    now=$(date +%s)
    if flag_mtime=$(stat -c %Y "$VPN_SETUP_FLAG" 2>/dev/null); then
        if (( now - flag_mtime >= AUTO_RESTART_STARTUP_GRACE )); then
            startup_done=true
            log "INFO" "Startup grace period over, counting health check failures"
            return 0
        fi
    elif (( now - watchdog_started_at >= AUTO_RESTART_SETUP_TIMEOUT )); then
        startup_done=true
        log "WARNING" "VPN setup has not completed after ${AUTO_RESTART_SETUP_TIMEOUT}s ($VPN_SETUP_FLAG missing), counting health check failures anyway"
        return 0
    fi

    if [[ "$startup_wait_logged" != "true" ]]; then
        startup_wait_logged=true
        log "INFO" "Waiting for VPN setup plus a ${AUTO_RESTART_STARTUP_GRACE}s grace period before counting failures"
    fi
    return 1
}

# One pass of the monitor. Only a status the health check has written since
# the previous pass counts toward a streak, so re-reading the same file does
# not look like sustained health or sustained failure.
monitor_once() {
    startup_complete || return 0

    refresh_status_if_stale

    local status_timestamp
    status_timestamp=$(jq -r '.timestamp // ""' "$STATUS_FILE" 2>/dev/null || echo "")
    if [[ -z "$status_timestamp" ]] || [[ "$status_timestamp" == "$last_status_timestamp" ]]; then
        return 0
    fi
    last_status_timestamp="$status_timestamp"

    local health_status=$(get_health_status || true)
    log "DEBUG" "Current health status: $health_status"

    # VPN
    if [[ "$RESTART_ON_VPN_FAILURE" == "true" ]]; then
        if vpn_failed; then
            vpn_ok_streak=0
            vpn_fail_streak=$((vpn_fail_streak + 1))
            log "WARNING" "VPN failure detected (interface: $(get_check_status vpn_interface || true), connectivity: $(get_check_status vpn_connectivity || true), $vpn_fail_streak/$RESTART_FAILURE_THRESHOLD)"

            if [[ $vpn_fail_streak -ge $RESTART_FAILURE_THRESHOLD ]]; then
                send_notification "vpn_failure" "VPN is not passing traffic, attempting restart"
                if restart_vpn; then
                    send_notification "vpn_restart_success" "VPN successfully restarted"
                else
                    send_notification "vpn_restart_failed" "VPN restart failed"
                fi
                vpn_fail_streak=0
            fi
        elif vpn_ok; then
            vpn_fail_streak=0
            vpn_ok_streak=$((vpn_ok_streak + 1))
            if [[ $vpn_ok_streak -ge $HEALTHY_CHECKS_BEFORE_RESET ]] && [[ $(get_restart_count "$VPN_RESTART_COUNT_FILE") -ne 0 ]]; then
                reset_restart_count "$VPN_RESTART_COUNT_FILE"
                gave_up_vpn=false
                log "INFO" "VPN healthy for $vpn_ok_streak consecutive checks, reset restart counter"
            fi
        fi
    fi

    # NZBGet
    if [[ "$RESTART_ON_NZBGET_FAILURE" == "true" ]]; then
        local nzbget_status=$(get_check_status "nzbget" || true)
        if [[ "$nzbget_status" == "failed" ]]; then
            nzbget_ok_streak=0
            nzbget_fail_streak=$((nzbget_fail_streak + 1))
            log "WARNING" "NZBGet failure detected ($nzbget_fail_streak/$RESTART_FAILURE_THRESHOLD)"

            if [[ $nzbget_fail_streak -ge $RESTART_FAILURE_THRESHOLD ]]; then
                send_notification "nzbget_failure" "NZBGet is not responding, attempting restart"
                if restart_nzbget; then
                    send_notification "nzbget_restart_success" "NZBGet successfully restarted"
                else
                    send_notification "nzbget_restart_failed" "NZBGet restart failed"
                fi
                nzbget_fail_streak=0
            fi
        elif [[ "$nzbget_status" == "success" ]]; then
            nzbget_fail_streak=0
            nzbget_ok_streak=$((nzbget_ok_streak + 1))
            if [[ $nzbget_ok_streak -ge $HEALTHY_CHECKS_BEFORE_RESET ]] && [[ $(get_restart_count "$NZBGET_RESTART_COUNT_FILE") -ne 0 ]]; then
                reset_restart_count "$NZBGET_RESTART_COUNT_FILE"
                gave_up_nzbget=false
                log "INFO" "NZBGet healthy for $nzbget_ok_streak consecutive checks, reset restart counter"
            fi
        fi
    fi
}

# Main monitoring function
monitor_and_restart() {
    log "INFO" "Starting auto-restart monitoring (enabled: $ENABLE_AUTO_RESTART)"

    if [[ "$ENABLE_AUTO_RESTART" != "true" ]]; then
        log "INFO" "Auto-restart disabled, exiting"
        return 0
    fi

    log "INFO" "Max restart attempts: $MAX_RESTART_ATTEMPTS, cooldown: ${RESTART_COOLDOWN_SECONDS}s, failure threshold: $RESTART_FAILURE_THRESHOLD, startup grace: ${AUTO_RESTART_STARTUP_GRACE}s, exit on max restarts: $EXIT_ON_MAX_RESTARTS"

    while true; do
        monitor_once
        sleep "$AUTO_RESTART_CHECK_INTERVAL"
    done
}

# Signal handlers
cleanup() {
    log "INFO" "Auto-restart monitor shutting down"
    exit 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap cleanup SIGTERM SIGINT

    # Ensure log directory exists
    mkdir -p "$(dirname "$RESTART_LOG")"

    # Start monitoring
    monitor_and_restart
fi
