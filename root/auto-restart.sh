#!/bin/bash

# Auto-restart script for nzbgetvpn
# Monitors health status and automatically restarts failed services

set -euo pipefail

# Configuration
RESTART_LOG="/config/auto-restart.log"
STATUS_FILE="/tmp/nzbgetvpn_status.json"
RESTART_COOLDOWN_SECONDS=${RESTART_COOLDOWN_SECONDS:-300}  # 5 minutes
MAX_RESTART_ATTEMPTS=${MAX_RESTART_ATTEMPTS:-3}
ENABLE_AUTO_RESTART=${ENABLE_AUTO_RESTART:-false}
RESTART_ON_VPN_FAILURE=${RESTART_ON_VPN_FAILURE:-true}
RESTART_ON_NZBGET_FAILURE=${RESTART_ON_NZBGET_FAILURE:-true}

# State files
LAST_VPN_RESTART_FILE="/tmp/last_vpn_restart"
LAST_NZBGET_RESTART_FILE="/tmp/last_nzbget_restart"
VPN_RESTART_COUNT_FILE="/tmp/vpn_restart_count"
NZBGET_RESTART_COUNT_FILE="/tmp/nzbget_restart_count"

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

# Update restart count
update_restart_count() {
    local count_file="$1"
    local current_count=0
    
    if [[ -f "$count_file" ]]; then
        current_count=$(cat "$count_file")
    fi
    
    current_count=$((current_count + 1))
    echo "$current_count" > "$count_file"
    
    echo "$current_count"
}

# Reset restart count (call when service is healthy for a while)
reset_restart_count() {
    local count_file="$1"
    echo "0" > "$count_file"
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
        log "ERROR" "Maximum VPN restart attempts ($MAX_RESTART_ATTEMPTS) exceeded"
        return 1
    fi
    
    log "INFO" "Restarting VPN (attempt $restart_count/$MAX_RESTART_ATTEMPTS)"
    
    # Update last restart time
    date +%s > "$LAST_VPN_RESTART_FILE"
    
    # Try to restart VPN processes
    local restart_success=false
    
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
    if [[ -f "/etc/cont-init.d/50-vpn-setup" ]]; then
        log "INFO" "Re-running VPN setup script"
        if bash /etc/cont-init.d/50-vpn-setup; then
            restart_success=true
            log "INFO" "VPN restart completed successfully"
        else
            log "ERROR" "VPN setup script failed"
        fi
    else
        log "ERROR" "VPN setup script not found"
    fi
    
    if $restart_success; then
        # Wait a bit and verify the restart worked
        sleep 10
        local vpn_status=$(get_check_status "vpn_interface")
        if [[ "$vpn_status" == "up" ]]; then
            log "INFO" "VPN restart verification successful"
            return 0
        else
            log "WARNING" "VPN restart verification failed - interface not up"
            return 1
        fi
    else
        return 1
    fi
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
        log "ERROR" "Maximum NZBGet restart attempts ($MAX_RESTART_ATTEMPTS) exceeded"
        return 1
    fi
    
    log "INFO" "Restarting NZBGet (attempt $restart_count/$MAX_RESTART_ATTEMPTS)"
    
    # Update last restart time
    date +%s > "$LAST_NZBGET_RESTART_FILE"
    
    # Try to restart NZBGet
    local restart_success=false
    
    # Stop NZBGet gracefully
    if pgrep nzbget >/dev/null 2>&1; then
        log "INFO" "Stopping NZBGet processes"
        pkill -TERM nzbget || true
        sleep 5
        
        # Force kill if still running
        if pgrep nzbget >/dev/null 2>&1; then
            pkill -KILL nzbget || true
            sleep 2
        fi
    fi
    
    # Start NZBGet via s6-overlay
    if command -v s6-svc >/dev/null 2>&1; then
        log "INFO" "Restarting NZBGet via s6-overlay"
        s6-svc -r /run/s6/services/nzbget 2>/dev/null || true
        sleep 5
    fi
    
    # Alternative: try to start NZBGet directly
    if ! pgrep nzbget >/dev/null 2>&1; then
        log "INFO" "Starting NZBGet directly"
        # This might need adjustment based on how the base image starts NZBGet
        nohup nzbget -D -c /config/nzbget.conf >/dev/null 2>&1 &
        sleep 5
    fi
    
    # Verify NZBGet is running
    if pgrep nzbget >/dev/null 2>&1; then
        restart_success=true
        log "INFO" "NZBGet restart completed successfully"
    else
        log "ERROR" "NZBGet restart failed - process not running"
    fi
    
    if $restart_success; then
        # Wait and verify the restart worked
        sleep 10
        local nzbget_status=$(get_check_status "nzbget")
        if [[ "$nzbget_status" == "success" ]]; then
            log "INFO" "NZBGet restart verification successful"
            return 0
        else
            log "WARNING" "NZBGet restart verification failed - service not responding"
            return 1
        fi
    else
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

# Main monitoring function
monitor_and_restart() {
    log "INFO" "Starting auto-restart monitoring (enabled: $ENABLE_AUTO_RESTART)"
    
    if [[ "$ENABLE_AUTO_RESTART" != "true" ]]; then
        log "INFO" "Auto-restart disabled, exiting"
        return 0
    fi
    
    local consecutive_healthy_checks=0
    local required_healthy_checks=5  # Reset restart counters after this many healthy checks
    
    while true; do
        # Get overall health status
        local health_status=$(get_health_status)
        log "DEBUG" "Current health status: $health_status"
        
        # Check if we need to restart anything
        local restart_needed=false
        
        # Check VPN status
        if [[ "$RESTART_ON_VPN_FAILURE" == "true" ]]; then
            local vpn_status=$(get_check_status "vpn_interface")
            if [[ "$vpn_status" == "down" ]] || [[ "$vpn_status" == "failed" ]]; then
                log "WARNING" "VPN interface failure detected"
                send_notification "vpn_failure" "VPN interface is down, attempting restart"
                
                if restart_vpn; then
                    send_notification "vpn_restart_success" "VPN successfully restarted"
                else
                    send_notification "vpn_restart_failed" "VPN restart failed"
                fi
                restart_needed=true
            fi
        fi
        
        # Check NZBGet status
        if [[ "$RESTART_ON_NZBGET_FAILURE" == "true" ]]; then
            local nzbget_status=$(get_check_status "nzbget")
            if [[ "$nzbget_status" == "failed" ]]; then
                log "WARNING" "NZBGet failure detected"
                send_notification "nzbget_failure" "NZBGet is not responding, attempting restart"
                
                if restart_nzbget; then
                    send_notification "nzbget_restart_success" "NZBGet successfully restarted"
                else
                    send_notification "nzbget_restart_failed" "NZBGet restart failed"
                fi
                restart_needed=true
            fi
        fi
        
        # Track consecutive healthy checks
        if [[ "$health_status" == "healthy" ]] && [[ "$restart_needed" == "false" ]]; then
            consecutive_healthy_checks=$((consecutive_healthy_checks + 1))
            
            # Reset restart counters after sustained health
            if [[ $consecutive_healthy_checks -ge $required_healthy_checks ]]; then
                reset_restart_count "$VPN_RESTART_COUNT_FILE"
                reset_restart_count "$NZBGET_RESTART_COUNT_FILE"
                consecutive_healthy_checks=0
                log "DEBUG" "Reset restart counters after sustained healthy status"
            fi
        else
            consecutive_healthy_checks=0
        fi
        
        # Sleep before next check
        sleep 60
    done
}

# Signal handlers
cleanup() {
    log "INFO" "Auto-restart monitor shutting down"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Ensure log directory exists
    mkdir -p "$(dirname "$RESTART_LOG")"
    
    # Start monitoring
    monitor_and_restart
fi 