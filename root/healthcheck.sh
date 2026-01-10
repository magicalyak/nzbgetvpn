#!/bin/bash

# Enhanced nzbgetvpn healthcheck with comprehensive monitoring
# Based on transmissionvpn healthcheck but adapted for NZBGet
# Exit codes:
# 0 = Healthy
# 1 = NZBGet not responding
# 2 = VPN interface down
# 3 = VPN interface not found
# 4 = VPN connectivity failed
# 5 = DNS resolution failed
# 6 = News server connectivity failed
# 7 = IP leak detected
# 8 = DNS leak detected

set -euo pipefail

# Configuration - Environment variables for customization
HEALTH_CHECK_HOST=${HEALTH_CHECK_HOST:-google.com}
CHECK_DNS_LEAK=${CHECK_DNS_LEAK:-false}
CHECK_IP_LEAK=${CHECK_IP_LEAK:-false}
CHECK_NEWS_SERVER=${CHECK_NEWS_SERVER:-true}
CHECK_VPN_CONNECTIVITY=${CHECK_VPN_CONNECTIVITY:-true}
HEALTH_CHECK_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-10}
EXTERNAL_IP_SERVICE=${EXTERNAL_IP_SERVICE:-ifconfig.me}
METRICS_ENABLED=${METRICS_ENABLED:-false}
ENABLE_VERBOSE_LOG=${DEBUG:-false}

# File locations
HEALTHCHECK_LOG="/config/healthcheck.log"
METRICS_FILE="/config/metrics.json"
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"
LAST_EXTERNAL_IP_FILE="/tmp/last_external_ip"
LAST_DNS_SERVERS_FILE="/tmp/last_dns_servers"
STATUS_FILE="/tmp/nzbgetvpn_status.json"
MAX_LOG_LINES=1000

# Ensure log directory exists
mkdir -p "$(dirname "$HEALTHCHECK_LOG")"
mkdir -p "$(dirname "$METRICS_FILE")"

# FIXED: Logging function that prevents debug output from interfering with function return values
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Output to log file and stderr (not stdout to avoid interfering with function returns)
    echo "[$timestamp] [$level] $message" | tee -a "$HEALTHCHECK_LOG" >&2
    
    # Also echo to stdout if verbose or if it's an error for visibility
    if [[ "$ENABLE_VERBOSE_LOG" == "true" ]] || [[ "$level" == "ERROR" ]]; then
        echo "[$timestamp] [$level] $message" >&2
    fi
    
    # Rotate log if it gets too large
    if [[ -f "$HEALTHCHECK_LOG" ]] && [[ $(wc -l < "$HEALTHCHECK_LOG") -gt $MAX_LOG_LINES ]]; then
        tail -n $((MAX_LOG_LINES / 2)) "$HEALTHCHECK_LOG" > "${HEALTHCHECK_LOG}.tmp"
        mv "${HEALTHCHECK_LOG}.tmp" "$HEALTHCHECK_LOG"
    fi
}

# Enhanced metrics collection function
update_metrics() {
    local check_type="$1"
    local status="$2"
    local response_time="${3:-0}"
    local details="${4:-}"
    
    if [[ "$METRICS_ENABLED" == "true" ]]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local metric="{\"timestamp\":\"$timestamp\",\"check\":\"$check_type\",\"status\":\"$status\",\"response_time\":$response_time,\"details\":\"$details\"}"
        
        # Initialize metrics file if it doesn't exist
        if [[ ! -f "$METRICS_FILE" ]]; then
            echo "[]" > "$METRICS_FILE"
        fi
        
        # Add new metric (keep last 100 entries)
        if command -v jq >/dev/null 2>&1; then
            jq ". += [$metric] | if length > 100 then .[1:] else . end" "$METRICS_FILE" > "${METRICS_FILE}.tmp" 2>/dev/null && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
        else
            # Fallback if jq is not available
            echo "[$metric]" > "$METRICS_FILE"
        fi
    fi
}

# Function to get external IP with multiple service fallbacks
get_external_ip() {
    local ip=""
    local start_time=$(date +%s.%N)
    local services=("$EXTERNAL_IP_SERVICE" "icanhazip.com" "ipecho.net/plain" "ip.me")
    
    # Try multiple IP detection services
    for service in "${services[@]}"; do
        if ip=$(timeout "$HEALTH_CHECK_TIMEOUT" curl -s --max-time 5 "$service" 2>/dev/null | tr -d '\n\r' | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'); then
            if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                local end_time=$(date +%s.%N)
                local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
                update_metrics "external_ip" "success" "$response_time" "$ip"
                echo "$ip"
                return 0
            fi
        fi
    done
    
    local end_time=$(date +%s.%N)
    local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    update_metrics "external_ip" "failed" "$response_time" ""
    return 1
}

# Function to check DNS resolution with improved error handling
check_dns() {
    local start_time=$(date +%s.%N)
    
    log "DEBUG" "Checking DNS resolution for $HEALTH_CHECK_HOST..."
    
    if timeout "$HEALTH_CHECK_TIMEOUT" nslookup "$HEALTH_CHECK_HOST" >/dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "dns" "success" "$response_time" "$HEALTH_CHECK_HOST"
        log "INFO" "DNS resolution successful for $HEALTH_CHECK_HOST (${response_time}s)"
        return 0
    else
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "dns" "failed" "$response_time" "$HEALTH_CHECK_HOST"
        log "ERROR" "DNS resolution failed for $HEALTH_CHECK_HOST (${response_time}s)"
        return 1
    fi
}

# Function to check NZBGet with improved error handling
check_nzbget() {
    local start_time=$(date +%s.%N)
    
    log "DEBUG" "Checking NZBGet web interface..."
    
    if timeout "$HEALTH_CHECK_TIMEOUT" curl -sSf --max-time 5 http://localhost:6789 >/dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "nzbget" "success" "$response_time" "http://localhost:6789"
        log "INFO" "NZBGet health check passed (${response_time}s)"
        
        # Additional check: Try to get NZBGet version/status if possible
        if timeout 5 curl -sSf http://localhost:6789/jsonrpc -d '{"method":"version"}' >/dev/null 2>&1; then
            log "DEBUG" "NZBGet JSON-RPC interface responding"
        fi
        
        return 0
    else
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "nzbget" "failed" "$response_time" "http://localhost:6789"
        log "ERROR" "NZBGet health check failed (${response_time}s)"
        return 1
    fi
}

# FIXED: Function to determine VPN interface - now properly isolates return value from debug output
# Check if running in external VPN mode
is_external_vpn_mode() {
    if [[ -f "/tmp/vpn_external_mode" ]]; then
        return 0
    fi
    if [[ -f "$VPN_INTERFACE_FILE" ]] && [[ "$(cat "$VPN_INTERFACE_FILE")" == "external" ]]; then
        return 0
    fi
    return 1
}

determine_vpn_interface() {
    local vpn_if=""

    if [[ -f "$VPN_INTERFACE_FILE" ]]; then
        vpn_if=$(cat "$VPN_INTERFACE_FILE")
        log "DEBUG" "VPN interface from file: $vpn_if"

        # External mode - return special value
        if [[ "$vpn_if" == "external" ]]; then
            echo "external"
            return 0
        fi
    else
        log "DEBUG" "VPN interface file not found, attempting to detect..."
        
        # Try to detect VPN interface
        if ip link show wg0 &> /dev/null; then
            vpn_if="wg0"
            log "DEBUG" "Detected WireGuard interface: wg0"
        elif ip link show tun0 &> /dev/null; then
            vpn_if="tun0"
            log "DEBUG" "Detected OpenVPN interface: tun0"
        else
            # Try to find any tun/wg interface
            for iface in $(ip link show | grep -E "(tun|wg)" | cut -d: -f2 | tr -d ' ' | head -5); do
                if [[ -n "$iface" ]]; then
                    vpn_if="$iface"
                    log "DEBUG" "Found VPN interface: $iface"
                    break
                fi
            done
        fi
        
        if [[ -z "$vpn_if" ]]; then
            log "ERROR" "Could not determine VPN interface"
            return 1
        fi
    fi
    
    # Return the interface name to stdout (this is what gets captured by the caller)
    echo "$vpn_if"
}

# Function to check VPN interface status
check_vpn_interface() {
    local vpn_if="$1"
    local start_time=$(date +%s.%N)
    
    log "DEBUG" "Checking VPN interface: $vpn_if"
    
    # Check if interface exists and is up
    if ip link show "$vpn_if" > /dev/null 2>&1; then
        if ip link show "$vpn_if" | grep -q "UP"; then
            local end_time=$(date +%s.%N)
            local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
            update_metrics "vpn_interface" "up" "$response_time" "$vpn_if"
            log "INFO" "VPN interface $vpn_if is UP (${response_time}s)"
            
            # Get interface statistics if available
            if [[ -f "/sys/class/net/$vpn_if/statistics/rx_bytes" ]]; then
                local rx_bytes tx_bytes
                rx_bytes=$(cat "/sys/class/net/$vpn_if/statistics/rx_bytes")
                tx_bytes=$(cat "/sys/class/net/$vpn_if/statistics/tx_bytes")
                log "DEBUG" "VPN interface stats - RX: ${rx_bytes} bytes, TX: ${tx_bytes} bytes"
                update_metrics "vpn_interface_rx" "info" "0" "$rx_bytes"
                update_metrics "vpn_interface_tx" "info" "0" "$tx_bytes"
            fi
            
            return 0
        else
            local end_time=$(date +%s.%N)
            local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
            update_metrics "vpn_interface" "down" "$response_time" "$vpn_if"
            log "ERROR" "VPN interface $vpn_if exists but is DOWN (${response_time}s)"
            return 1
        fi
    else
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "vpn_interface" "missing" "$response_time" "$vpn_if"
        log "ERROR" "VPN interface $vpn_if does not exist (${response_time}s)"
        return 1
    fi
}

# Function to check VPN connectivity
check_vpn_connectivity() {
    local vpn_if="$1"
    local start_time=$(date +%s.%N)
    
    if [[ "$CHECK_VPN_CONNECTIVITY" != "true" ]]; then
        log "DEBUG" "VPN connectivity check disabled"
        return 0
    fi
    
    log "DEBUG" "Testing VPN connectivity to $HEALTH_CHECK_HOST through $vpn_if"
    
    # Ping test through VPN interface
    if timeout "$HEALTH_CHECK_TIMEOUT" ping -c 1 -W 3 -I "$vpn_if" "$HEALTH_CHECK_HOST" > /dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "vpn_connectivity" "success" "$response_time" "$HEALTH_CHECK_HOST"
        log "INFO" "VPN connectivity test successful (${response_time}s)"
        return 0
    else
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "vpn_connectivity" "failed" "$response_time" "$HEALTH_CHECK_HOST"
        log "ERROR" "VPN connectivity test failed to $HEALTH_CHECK_HOST (${response_time}s)"
        return 1
    fi
}

# Function to check for IP leaks
check_ip_leak() {
    if [[ "$CHECK_IP_LEAK" != "true" ]]; then
        log "DEBUG" "IP leak check disabled"
        return 0
    fi
    
    log "DEBUG" "Checking for IP leaks..."
    
    # Get current external IP
    local external_ip
    if external_ip=$(get_external_ip); then
        log "INFO" "Current external IP: $external_ip"
        
        # Store IP for comparison (basic leak detection)
        local previous_ip=""
        if [[ -f "$LAST_EXTERNAL_IP_FILE" ]]; then
            previous_ip=$(cat "$LAST_EXTERNAL_IP_FILE")
        fi
        
        echo "$external_ip" > "$LAST_EXTERNAL_IP_FILE"
        
        # Simple check: if we have a previous IP and it changed, log it
        if [[ -n "$previous_ip" ]] && [[ "$previous_ip" != "$external_ip" ]]; then
            log "WARN" "External IP changed from $previous_ip to $external_ip"
            update_metrics "ip_leak" "changed" "0" "from:$previous_ip,to:$external_ip"
        else
            update_metrics "ip_leak" "stable" "0" "$external_ip"
        fi
        
        return 0
    else
        log "ERROR" "Failed to check external IP"
        return 1
    fi
}

# Function to check DNS leaks
check_dns_leak() {
    if [[ "$CHECK_DNS_LEAK" != "true" ]]; then
        log "DEBUG" "DNS leak check disabled"
        return 0
    fi
    
    log "DEBUG" "Checking for DNS leaks..."
    
    # Check which DNS servers are being used
    local dns_servers
    if dns_servers=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ',' | sed 's/,$//'); then
        log "INFO" "Current DNS servers: $dns_servers"
        
        # Store for comparison
        local previous_dns=""
        if [[ -f "$LAST_DNS_SERVERS_FILE" ]]; then
            previous_dns=$(cat "$LAST_DNS_SERVERS_FILE")
        fi
        
        echo "$dns_servers" > "$LAST_DNS_SERVERS_FILE"
        
        # Simple check: if DNS servers changed, log it
        if [[ -n "$previous_dns" ]] && [[ "$previous_dns" != "$dns_servers" ]]; then
            log "WARN" "DNS servers changed from $previous_dns to $dns_servers"
            update_metrics "dns_leak" "changed" "0" "from:$previous_dns,to:$dns_servers"
        else
            update_metrics "dns_leak" "stable" "0" "$dns_servers"
        fi
        
        return 0
    else
        log "ERROR" "Failed to check DNS servers"
        return 1
    fi
}

# Function to check news server connectivity
check_news_server() {
    if [[ "$CHECK_NEWS_SERVER" != "true" ]]; then
        log "DEBUG" "News server check disabled"
        return 0
    fi
    
    # Read from NZBGet config file instead of environment variables
    local news_host news_port
    news_host=$(grep "^Server1.Host=" /config/nzbget.conf 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo "")
    news_port=$(grep "^Server1.Port=" /config/nzbget.conf 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo "563")
    
    if [[ -z "$news_host" ]]; then
        log "DEBUG" "No news server configured for health check"
        return 0
    fi
    
    local start_time=$(date +%s.%N)
    
    log "DEBUG" "Checking news server connectivity: $news_host:$news_port"
    
    if timeout "$HEALTH_CHECK_TIMEOUT" bash -c "</dev/tcp/$news_host/$news_port" 2>/dev/null; then
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "news_server" "success" "$response_time" "$news_host:$news_port"
        log "INFO" "News server connectivity check passed: $news_host:$news_port (${response_time}s)"
        return 0
    else
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "news_server" "failed" "$response_time" "$news_host:$news_port"
        log "WARNING" "News server connectivity check failed: $news_host:$news_port (${response_time}s)"
        return 1
    fi
}

# Function to collect system metrics
collect_system_metrics() {
    if [[ "$METRICS_ENABLED" != "true" ]]; then
        return 0
    fi
    
    log "DEBUG" "Collecting system metrics..."
    
    # Memory usage
    if [[ -f /proc/meminfo ]]; then
        local mem_total mem_available mem_used mem_percent
        mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        mem_used=$((mem_total - mem_available))
        mem_percent=$(awk "BEGIN {printf \"%.2f\", ($mem_used/$mem_total)*100}")
        update_metrics "system_memory" "info" "0" "used:$mem_used,total:$mem_total,percent:$mem_percent"
    fi
    
    # Load average
    if [[ -f /proc/loadavg ]]; then
        local load_1min load_5min load_15min
        read load_1min load_5min load_15min _ _ < /proc/loadavg
        update_metrics "system_load" "info" "0" "1min:$load_1min,5min:$load_5min,15min:$load_15min"
    fi
    
    # Disk usage for important paths
    for path in /config /downloads /tmp; do
        if [[ -d "$path" ]]; then
            local disk_usage
            disk_usage=$(df "$path" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
            update_metrics "system_disk" "info" "0" "path:$path,usage:$disk_usage"
        fi
    done
    
    # Network statistics
    local total_rx=0 total_tx=0
    for iface in /sys/class/net/*; do
        iface=$(basename "$iface")
        if [[ -f "/sys/class/net/$iface/statistics/rx_bytes" ]]; then
            local rx tx
            rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo "0")
            tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo "0")
            total_rx=$((total_rx + rx))
            total_tx=$((total_tx + tx))
        fi
    done
    update_metrics "system_network" "info" "0" "rx:$total_rx,tx:$total_tx"
}

# Main health check execution
main() {
    log "INFO" "Starting enhanced health check..."
    local overall_status="healthy"
    local exit_code=0
    local status_checks=()
    
    # Initialize metrics
    if [[ "$METRICS_ENABLED" == "true" ]]; then
        collect_system_metrics
    fi
    
    # Check 1: NZBGet responsiveness
    if check_nzbget; then
        status_checks+=("nzbget:success")
    else
        overall_status="unhealthy"
        exit_code=1
        status_checks+=("nzbget:failed")
    fi
    
    # Check 2: VPN interface
    if vpn_interface=$(determine_vpn_interface); then
        if [[ "$vpn_interface" == "external" ]]; then
            # External VPN mode - skip interface check, rely on IP leak detection
            log "DEBUG" "External VPN mode - skipping interface check"
            status_checks+=("vpn_interface:external")

            # In external mode, verify VPN is working by checking external IP
            local current_ip=$(get_external_ip)
            local expected_ip=""
            if [[ -f "/tmp/expected_vpn_ip" ]]; then
                expected_ip=$(cat /tmp/expected_vpn_ip)
            fi

            if [[ -n "$current_ip" ]] && [[ -n "$expected_ip" ]]; then
                if [[ "$current_ip" == "$expected_ip" ]]; then
                    status_checks+=("vpn_connectivity:success")
                    log "DEBUG" "External VPN check passed - IP matches: $current_ip"
                else
                    # IP changed - VPN may have failed
                    overall_status="unhealthy"
                    [[ $exit_code -eq 0 ]] && exit_code=7
                    status_checks+=("vpn_connectivity:failed")
                    status_checks+=("ip_leak:detected")
                    log "ERROR" "External VPN failure - IP changed from $expected_ip to $current_ip"
                fi
            elif [[ -z "$current_ip" ]]; then
                # Can't reach internet - network issue
                if [[ "$overall_status" == "healthy" ]]; then
                    overall_status="degraded"
                fi
                [[ $exit_code -eq 0 ]] && exit_code=4
                status_checks+=("vpn_connectivity:failed")
                log "WARNING" "Cannot determine external IP - network may be down"
            else
                # No expected IP recorded, just check we have connectivity
                status_checks+=("vpn_connectivity:success")
            fi
        elif check_vpn_interface "$vpn_interface"; then
            status_checks+=("vpn_interface:up")

            # Check 3: VPN connectivity (if interface is up)
            if check_vpn_connectivity "$vpn_interface"; then
                status_checks+=("vpn_connectivity:success")
            else
                if [[ "$overall_status" == "healthy" ]]; then
                    overall_status="degraded"
                fi
                [[ $exit_code -eq 0 ]] && exit_code=4
                status_checks+=("vpn_connectivity:failed")
            fi
        else
            overall_status="unhealthy"
            [[ $exit_code -eq 0 ]] && exit_code=2
            status_checks+=("vpn_interface:down")
        fi
    else
        overall_status="unhealthy"
        [[ $exit_code -eq 0 ]] && exit_code=3
        status_checks+=("vpn_interface:missing")
    fi
    
    # Check 4: DNS resolution
    if check_dns; then
        status_checks+=("dns:success")
    else
        if [[ "$overall_status" == "healthy" ]]; then
            overall_status="degraded"
        fi
        [[ $exit_code -eq 0 ]] && exit_code=5
        status_checks+=("dns:failed")
    fi
    
    # Check 5: News server connectivity (optional, non-critical)
    if check_news_server; then
        status_checks+=("news_server:success")
    else
        if [[ "$overall_status" == "healthy" ]]; then
            overall_status="warning"
        fi
        [[ $exit_code -eq 0 ]] && exit_code=6
        status_checks+=("news_server:failed")
    fi
    
    # Check 6: IP leak detection (optional, non-critical)
    if check_ip_leak; then
        status_checks+=("ip_leak:stable")
    else
        if [[ "$overall_status" == "healthy" ]]; then
            overall_status="warning"
        fi
        [[ $exit_code -eq 0 ]] && exit_code=7
        status_checks+=("ip_leak:failed")
    fi
    
    # Check 7: DNS leak detection (optional, non-critical)
    if check_dns_leak; then
        status_checks+=("dns_leak:stable")
    else
        if [[ "$overall_status" == "healthy" ]]; then
            overall_status="warning"
        fi
        [[ $exit_code -eq 0 ]] && exit_code=8
        status_checks+=("dns_leak:failed")
    fi
    
    # Update overall status metric
    update_metrics "overall" "$overall_status" "0" "exit_code=$exit_code"
    
    log "INFO" "Health check completed: $overall_status (exit code: $exit_code)"
    
    # Create comprehensive status file for external monitoring
    local external_ip
    external_ip=$(get_external_ip 2>/dev/null || echo 'unknown')
    
    cat > "$STATUS_FILE" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "status": "$overall_status",
    "exit_code": $exit_code,
    "vpn_interface": "${vpn_interface:-unknown}",
    "external_ip": "$external_ip",
    "configuration": {
        "check_dns_leak": $CHECK_DNS_LEAK,
        "check_ip_leak": $CHECK_IP_LEAK,
        "check_news_server": $CHECK_NEWS_SERVER,
        "check_vpn_connectivity": $CHECK_VPN_CONNECTIVITY,
        "health_check_host": "$HEALTH_CHECK_HOST",
        "health_check_timeout": $HEALTH_CHECK_TIMEOUT,
        "external_ip_service": "$EXTERNAL_IP_SERVICE",
        "metrics_enabled": $METRICS_ENABLED
    },
    "checks": {
        "nzbget": "$(echo "${status_checks[@]}" | grep -o 'nzbget:[^[:space:]]*' | cut -d: -f2 || echo 'unknown')",
        "vpn_interface": "$(echo "${status_checks[@]}" | grep -o 'vpn_interface:[^[:space:]]*' | cut -d: -f2 || echo 'unknown')",
        "vpn_connectivity": "$(echo "${status_checks[@]}" | grep -o 'vpn_connectivity:[^[:space:]]*' | cut -d: -f2 || echo 'unknown')",
        "dns": "$(echo "${status_checks[@]}" | grep -o 'dns:[^[:space:]]*' | cut -d: -f2 || echo 'unknown')",
        "news_server": "$(echo "${status_checks[@]}" | grep -o 'news_server:[^[:space:]]*' | cut -d: -f2 || echo 'unknown')",
        "ip_leak": "$(echo "${status_checks[@]}" | grep -o 'ip_leak:[^[:space:]]*' | cut -d: -f2 || echo 'unknown')",
        "dns_leak": "$(echo "${status_checks[@]}" | grep -o 'dns_leak:[^[:space:]]*' | cut -d: -f2 || echo 'unknown')"
    }
}
EOF
    
    exit $exit_code
}

# Execute main function
main "$@"
