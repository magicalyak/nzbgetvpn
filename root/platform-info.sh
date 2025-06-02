#!/bin/bash

# Platform Information Script for nzbgetvpn
# Provides detailed information about the running platform and architecture

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Function to print section headers
print_header() {
    echo
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$CYAN" "  $1"
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to detect platform type
detect_platform_type() {
    local arch=$(uname -m)
    local platform=""
    
    case "$arch" in
        "x86_64"|"amd64")
            platform="x86_64 (AMD64)"
            ;;
        "aarch64"|"arm64")
            platform="ARM64"
            # Try to detect specific ARM platform
            if [ -f /proc/cpuinfo ]; then
                if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
                    platform="ARM64 (Raspberry Pi)"
                elif grep -q "BCM" /proc/cpuinfo 2>/dev/null; then
                    platform="ARM64 (Broadcom)"
                elif [ -f /proc/device-tree/model ] && grep -q "Apple" /proc/device-tree/model 2>/dev/null; then
                    platform="ARM64 (Apple Silicon)"
                fi
            fi
            ;;
        "armv7l"|"armhf")
            platform="ARM32 (ARMv7)"
            ;;
        *)
            platform="$arch (Unknown)"
            ;;
    esac
    
    echo "$platform"
}

# Function to get CPU information
get_cpu_info() {
    local cpu_info="Unknown"
    
    if [ -f /proc/cpuinfo ]; then
        # Try different fields depending on architecture
        cpu_info=$(grep -E "^(model name|Hardware|cpu model)" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^ *//' 2>/dev/null || echo "Unknown")
        
        if [ "$cpu_info" = "Unknown" ] || [ -z "$cpu_info" ]; then
            # Fallback to processor info
            cpu_info=$(grep -E "^processor" /proc/cpuinfo | wc -l 2>/dev/null || echo "Unknown")
            if [ "$cpu_info" != "Unknown" ]; then
                cpu_info="$cpu_info cores"
            fi
        fi
    fi
    
    echo "$cpu_info"
}

# Function to get memory information
get_memory_info() {
    if [ -f /proc/meminfo ]; then
        local mem_total=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}' 2>/dev/null || echo "0")
        local mem_available=$(grep "^MemAvailable:" /proc/meminfo | awk '{print $2}' 2>/dev/null || echo "0")
        
        if [ "$mem_total" != "0" ]; then
            local mem_total_mb=$((mem_total / 1024))
            local mem_total_gb=$((mem_total_mb / 1024))
            local mem_available_mb=$((mem_available / 1024))
            local usage_percent=0
            
            if [ "$mem_available" != "0" ]; then
                usage_percent=$(((mem_total - mem_available) * 100 / mem_total))
            fi
            
            echo "${mem_total_gb}GB total, ${mem_available_mb}MB available (${usage_percent}% used)"
        else
            echo "Unknown"
        fi
    else
        echo "Unknown"
    fi
}

# Function to check container runtime
get_container_info() {
    local runtime="Unknown"
    
    if [ -f /.dockerenv ]; then
        runtime="Docker"
        
        # Try to get more specific Docker info
        if command -v docker >/dev/null 2>&1; then
            local docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1 || echo "")
            if [ -n "$docker_version" ]; then
                runtime="Docker $docker_version"
            fi
        fi
    elif [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
        runtime="Kubernetes"
    elif [ -n "${PODMAN_VERSION:-}" ]; then
        runtime="Podman"
    elif grep -q "lxc\|docker" /proc/1/cgroup 2>/dev/null; then
        runtime="Container (LXC/Docker)"
    fi
    
    echo "$runtime"
}

# Function to check VPN capabilities
check_vpn_capabilities() {
    local openvpn_available="❌"
    local wireguard_available="❌"
    local tun_device="❌"
    
    # Check OpenVPN
    if command -v openvpn >/dev/null 2>&1; then
        openvpn_available="✅ $(openvpn --version 2>/dev/null | head -1 | awk '{print $2}' || echo 'Available')"
    fi
    
    # Check WireGuard
    if command -v wg >/dev/null 2>&1; then
        wireguard_available="✅ $(wg --version 2>/dev/null || echo 'Available')"
    fi
    
    # Check TUN device
    if [ -c /dev/net/tun ]; then
        tun_device="✅ Available"
    elif [ -e /dev/net/tun ]; then
        tun_device="⚠️  Exists but not accessible"
    fi
    
    echo -e "  OpenVPN:   $openvpn_available"
    echo -e "  WireGuard: $wireguard_available"
    echo -e "  TUN Device: $tun_device"
}

# Function to check platform optimizations
check_platform_optimizations() {
    local arch="${TARGETARCH:-$(uname -m)}"
    
    case "$arch" in
        "arm64"|"aarch64")
            print_color "$GREEN" "✅ ARM64 optimizations enabled:"
            echo "   • Enhanced network buffer sizes"
            echo "   • ARM-specific performance tuning"
            echo "   • Optimized for low-power operation"
            ;;
        "amd64"|"x86_64")
            print_color "$GREEN" "✅ AMD64 optimizations enabled:"
            echo "   • Standard x86_64 performance profile"
            echo "   • Optimized for server workloads"
            ;;
        *)
            print_color "$YELLOW" "⚠️  Default configuration (no specific optimizations)"
            ;;
    esac
}

# Function to check monitoring capabilities
check_monitoring_capabilities() {
    local python_available="❌"
    local monitoring_enabled="❌"
    local jq_available="❌"
    
    # Check Python
    if command -v python3 >/dev/null 2>&1; then
        python_available="✅ $(python3 --version 2>/dev/null | cut -d' ' -f2 || echo 'Available')"
    fi
    
    # Check jq
    if command -v jq >/dev/null 2>&1; then
        jq_available="✅ $(jq --version 2>/dev/null | cut -d'-' -f2 || echo 'Available')"
    fi
    
    # Check monitoring setting
    if [ "${ENABLE_MONITORING:-yes}" = "yes" ]; then
        monitoring_enabled="✅ Enabled (port ${MONITORING_PORT:-8080})"
    else
        monitoring_enabled="❌ Disabled"
    fi
    
    echo -e "  Python3:    $python_available"
    echo -e "  jq:         $jq_available"
    echo -e "  Monitoring: $monitoring_enabled"
}

# Function to display build information
show_build_info() {
    echo -e "  Build Platform:  ${BUILDPLATFORM:-Unknown}"
    echo -e "  Target Platform: ${TARGETPLATFORM:-Unknown}"
    echo -e "  Target Arch:     ${TARGETARCH:-Unknown}"
    echo -e "  Build Date:      $(date -r /root/platform-info.sh 2>/dev/null || echo 'Unknown')"
}

# Function to show performance recommendations
show_performance_recommendations() {
    local arch="${TARGETARCH:-$(uname -m)}"
    
    case "$arch" in
        "arm64"|"aarch64")
            echo "🔧 ARM64 Performance Tips:"
            echo "   • Use WireGuard for better performance on ARM"
            echo "   • Consider reducing connection count for news servers"
            echo "   • Monitor temperature if running on Raspberry Pi"
            echo "   • Use SD card class 10 or better for storage"
            ;;
        "amd64"|"x86_64")
            echo "🔧 AMD64 Performance Tips:"
            echo "   • OpenVPN and WireGuard both perform well"
            echo "   • Higher connection counts generally work better"
            echo "   • Consider using SSD storage for optimal performance"
            ;;
        *)
            echo "🔧 General Performance Tips:"
            echo "   • Start with conservative settings and adjust"
            echo "   • Monitor system resources during operation"
            ;;
    esac
}

# Main execution
main() {
    clear
    print_color "$PURPLE" "╔═══════════════════════════════════════════════════════════════════════════════╗"
    print_color "$PURPLE" "║                              🐳 nzbgetvpn                                    ║"
    print_color "$PURPLE" "║                      Multi-Architecture Platform Info                        ║"
    print_color "$PURPLE" "╚═══════════════════════════════════════════════════════════════════════════════╝"
    
    print_header "🖥️  System Information"
    echo -e "  Architecture:    $(detect_platform_type)"
    echo -e "  Kernel:          $(uname -s) $(uname -r)"
    echo -e "  CPU:             $(get_cpu_info)"
    echo -e "  Memory:          $(get_memory_info)"
    echo -e "  Container:       $(get_container_info)"
    
    print_header "🏗️  Build Information"
    show_build_info
    
    print_header "🛡️  VPN Capabilities"
    check_vpn_capabilities
    
    print_header "📊 Monitoring Capabilities"
    check_monitoring_capabilities
    
    print_header "⚡ Platform Optimizations"
    check_platform_optimizations
    
    print_header "💡 Performance Recommendations"
    show_performance_recommendations
    
    print_header "🔗 Useful Commands"
    echo "  View real-time logs:     docker logs -f nzbgetvpn"
    echo "  Check health status:     curl http://localhost:8080/health"
    echo "  View monitoring:         curl http://localhost:8080/"
    echo "  Container shell:         docker exec -it nzbgetvpn bash"
    echo "  Check VPN status:        docker exec nzbgetvpn ip addr show"
    
    echo
    print_color "$GREEN" "✅ Platform information displayed successfully!"
    echo
}

# Help function
show_help() {
    echo "nzbgetvpn Platform Information Script"
    echo
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -q, --quiet    Quiet mode (minimal output)"
    echo "  -j, --json     Output in JSON format"
    echo
}

# JSON output function
json_output() {
    local arch="${TARGETARCH:-$(uname -m)}"
    local platform=$(detect_platform_type)
    local cpu=$(get_cpu_info)
    local memory=$(get_memory_info)
    local container=$(get_container_info)
    
    cat << EOF
{
  "nzbgetvpn": {
    "system": {
      "architecture": "$arch",
      "platform": "$platform",
      "kernel": "$(uname -s) $(uname -r)",
      "cpu": "$cpu",
      "memory": "$memory",
      "container": "$container"
    },
    "build": {
      "buildplatform": "${BUILDPLATFORM:-unknown}",
      "targetplatform": "${TARGETPLATFORM:-unknown}",
      "targetarch": "${TARGETARCH:-unknown}"
    },
    "capabilities": {
      "openvpn": $(command -v openvpn >/dev/null && echo "true" || echo "false"),
      "wireguard": $(command -v wg >/dev/null && echo "true" || echo "false"),
      "python3": $(command -v python3 >/dev/null && echo "true" || echo "false"),
      "monitoring": $([ "${ENABLE_MONITORING:-yes}" = "yes" ] && echo "true" || echo "false"),
      "tun_device": $([ -c /dev/net/tun ] && echo "true" || echo "false")
    }
  }
}
EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -q|--quiet)
        echo "$(detect_platform_type) | $(get_cpu_info)"
        exit 0
        ;;
    -j|--json)
        json_output
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac 