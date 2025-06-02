#!/bin/bash

# Enhanced nzbgetvpn healthcheck with detailed monitoring
# Exit codes:
# 0 = Healthy
# 1 = NZBGet not responding
# 2 = VPN interface down
# 3 = VPN interface not found
# 4 = External IP leaked (not using VPN)
# 5 = DNS resolution failed
# 6 = News server connectivity failed

set -euo pipefail

# Configuration
HEALTHCHECK_LOG="/config/healthcheck.log"
METRICS_FILE="/config/metrics.json"
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"
MAX_LOG_LINES=1000
ENABLE_VERBOSE_LOG=${DEBUG:-false}

# Ensure log directory exists
mkdir -p "$(dirname "$HEALTHCHECK_LOG")"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$HEALTHCHECK_LOG"
    
    # Also echo to stdout if verbose or if it's an error
    if [[ "$ENABLE_VERBOSE_LOG" == "true" ]] || [[ "$level" == "ERROR" ]]; then
        echo "[$timestamp] [$level] $message" >&2
    fi
    
    # Rotate log if it gets too large
    if [[ -f "$HEALTHCHECK_LOG" ]] && [[ $(wc -l < "$HEALTHCHECK_LOG") -gt $MAX_LOG_LINES ]]; then
        tail -n $((MAX_LOG_LINES / 2)) "$HEALTHCHECK_LOG" > "${HEALTHCHECK_LOG}.tmp"
        mv "${HEALTHCHECK_LOG}.tmp" "$HEALTHCHECK_LOG"
    fi
}

# Metrics collection function
update_metrics() {
    local check_type="$1"
    local status="$2"
    local response_time="${3:-0}"
    local details="${4:-}"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local metric="{\"timestamp\":\"$timestamp\",\"check\":\"$check_type\",\"status\":\"$status\",\"response_time\":$response_time,\"details\":\"$details\"}"
    
    # Initialize metrics file if it doesn't exist
    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "[]" > "$METRICS_FILE"
    fi
    
    # Add new metric (keep last 100 entries)
    jq ". += [$metric] | if length > 100 then .[1:] else . end" "$METRICS_FILE" > "${METRICS_FILE}.tmp" 2>/dev/null || {
        # Fallback if jq is not available
        echo "[$metric]" > "$METRICS_FILE"
    }
    [[ -f "${METRICS_FILE}.tmp" ]] && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
}

# Function to get external IP
get_external_ip() {
    local ip=""
    local start_time=$(date +%s.%N)
    
    # Try multiple IP detection services
    for service in "ifconfig.me" "icanhazip.com" "ipecho.net/plain"; do
        if ip=$(timeout 10 curl -s --max-time 5 "$service" 2>/dev/null | tr -d '\n'); then
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

# Function to check DNS resolution
check_dns() {
    local start_time=$(date +%s.%N)
    
    if nslookup google.com >/dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "dns" "success" "$response_time" ""
        return 0
    else
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "dns" "failed" "$response_time" ""
        return 1
    fi
}

# Function to check NZBGet
check_nzbget() {
    local start_time=$(date +%s.%N)
    
    if curl -sSf --max-time 5 http://localhost:6789 >/dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "nzbget" "success" "$response_time" ""
        log "INFO" "NZBGet health check passed (${response_time}s)"
        return 0
    else
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "nzbget" "failed" "$response_time" ""
        log "ERROR" "NZBGet health check failed (${response_time}s)"
        return 1
    fi
}

# Function to determine VPN interface
determine_vpn_interface() {
    local vpn_if=""
    
    if [[ -f "$VPN_INTERFACE_FILE" ]]; then
        vpn_if=$(cat "$VPN_INTERFACE_FILE")
        log "INFO" "VPN interface from file: $vpn_if"
    else
        # Fallback detection
        if ip link show wg0 &> /dev/null; then
            vpn_if="wg0"
            log "INFO" "VPN interface detected (fallback): $vpn_if (WireGuard)"
        elif ip link show tun0 &> /dev/null; then
            vpn_if="tun0"
            log "INFO" "VPN interface detected (fallback): $vpn_if (OpenVPN)"
        else
            log "ERROR" "No VPN interface found (checked wg0, tun0)"
            return 1
        fi
    fi
    
    echo "$vpn_if"
    return 0
}

# Function to check VPN interface status
check_vpn_interface() {
    local vpn_if="$1"
    local start_time=$(date +%s.%N)
    
    if ip link show "$vpn_if" | grep -q "UP"; then
        # Additional checks for interface statistics
        local rx_bytes=$(cat "/sys/class/net/$vpn_if/statistics/rx_bytes" 2>/dev/null || echo "0")
        local tx_bytes=$(cat "/sys/class/net/$vpn_if/statistics/tx_bytes" 2>/dev/null || echo "0")
        local ip_addr=$(ip addr show "$vpn_if" | grep -oP 'inet \K[^/]+' | head -1 || echo "unknown")
        
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        
        local details="ip=$ip_addr,rx=${rx_bytes}b,tx=${tx_bytes}b"
        update_metrics "vpn_interface" "up" "$response_time" "$details"
        log "INFO" "VPN interface $vpn_if is UP ($details)"
        return 0
    else
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        update_metrics "vpn_interface" "down" "$response_time" ""
        log "ERROR" "VPN interface $vpn_if is DOWN"
        return 1
    fi
}

# Function to check if we're using the VPN (IP leak detection)
check_ip_leak() {
    # Skip IP leak check if disabled
    if [[ "${DISABLE_IP_LEAK_CHECK:-false}" == "true" ]]; then
        log "INFO" "IP leak check disabled"
        return 0
    fi
    
    # Get our expected VPN IP range from environment or config
    local expected_vpn_network="${VPN_NETWORK:-}"
    
    if external_ip=$(get_external_ip); then
        log "INFO" "External IP detected: $external_ip"
        
        # If we have a VPN network defined, check if our IP is in that range
        if [[ -n "$expected_vpn_network" ]]; then
            if echo "$external_ip" | grep -qE "^$(echo "$expected_vpn_network" | sed 's/\./\\./g' | sed 's/\*/[0-9]+/g')"; then
                log "INFO" "IP is within expected VPN network: $expected_vpn_network"
                return 0
            else
                log "ERROR" "IP leak detected: $external_ip not in VPN network $expected_vpn_network"
                return 1
            fi
        fi
        
        # Basic check: if IP looks like common ISP ranges, it might be leaked
        # This is a simple heuristic and not foolproof
        if [[ "$external_ip" =~ ^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]]; then
            log "WARNING" "External IP appears to be private/local: $external_ip"
        fi
        
        return 0
    else
        log "WARNING" "Could not determine external IP"
        return 1
    fi
}

# Function to check news server connectivity (optional)
check_news_server() {
    local news_host="${NZBGET_S1_HOST:-}"
    local news_port="${NZBGET_S1_PORT:-563}"
    
    if [[ -z "$news_host" ]]; then
        log "INFO" "No news server configured for health check"
        return 0
    fi
    
    local start_time=$(date +%s.%N)
    
    if timeout 10 bash -c "</dev/tcp/$news_host/$news_port" 2>/dev/null; then
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

# Main health check execution
main() {
    log "INFO" "Starting enhanced health check"
    local overall_status="healthy"
    local exit_code=0
    
    # Check 1: NZBGet responsiveness
    if ! check_nzbget; then
        overall_status="unhealthy"
        exit_code=1
    fi
    
    # Check 2: VPN interface
    if vpn_interface=$(determine_vpn_interface); then
        if ! check_vpn_interface "$vpn_interface"; then
            overall_status="unhealthy"
            [[ $exit_code -eq 0 ]] && exit_code=2
        fi
    else
        overall_status="unhealthy"
        [[ $exit_code -eq 0 ]] && exit_code=3
    fi
    
    # Check 3: DNS resolution
    if ! check_dns; then
        overall_status="degraded"
        [[ $exit_code -eq 0 ]] && exit_code=5
    fi
    
    # Check 4: IP leak detection (non-critical)
    if ! check_ip_leak; then
        if [[ "$overall_status" == "healthy" ]]; then
            overall_status="warning"
        fi
        [[ $exit_code -eq 0 ]] && exit_code=4
    fi
    
    # Check 5: News server connectivity (optional, non-critical)
    if ! check_news_server; then
        if [[ "$overall_status" == "healthy" ]]; then
            overall_status="warning"
        fi
        # Don't change exit code for news server failures
    fi
    
    # Update overall status metric
    update_metrics "overall" "$overall_status" "0" "exit_code=$exit_code"
    
    log "INFO" "Health check completed: $overall_status (exit code: $exit_code)"
    
    # Create status file for external monitoring
    cat > "/tmp/nzbgetvpn_status.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "status": "$overall_status",
    "exit_code": $exit_code,
    "vpn_interface": "${vpn_interface:-unknown}",
    "external_ip": "$(get_external_ip 2>/dev/null || echo 'unknown')",
    "checks": {
        "nzbget": "$(grep '"check":"nzbget"' "$METRICS_FILE" 2>/dev/null | tail -1 | jq -r '.status' 2>/dev/null || echo 'unknown')",
        "vpn_interface": "$(grep '"check":"vpn_interface"' "$METRICS_FILE" 2>/dev/null | tail -1 | jq -r '.status' 2>/dev/null || echo 'unknown')",
        "dns": "$(grep '"check":"dns"' "$METRICS_FILE" 2>/dev/null | tail -1 | jq -r '.status' 2>/dev/null || echo 'unknown')",
        "news_server": "$(grep '"check":"news_server"' "$METRICS_FILE" 2>/dev/null | tail -1 | jq -r '.status' 2>/dev/null || echo 'unknown')"
    }
}
EOF
    
    exit $exit_code
}

# Execute main function
main "$@"
