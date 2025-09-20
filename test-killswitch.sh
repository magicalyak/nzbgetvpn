#!/bin/bash
# Test script to verify VPN kill switch functionality
# This script performs various tests to ensure the kill switch prevents data leaks

set -e

CONTAINER_NAME="${1:-nzbgetvpn}"
VERBOSE="${2:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

echo "======================================"
echo "VPN Kill Switch Test Suite"
echo "Container: $CONTAINER_NAME"
echo "======================================"
echo ""

# Function to run command in container
exec_container() {
    docker exec "$CONTAINER_NAME" "$@"
}

# Function to print test result
print_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓${NC} $test_name: ${GREEN}PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name: ${RED}FAILED${NC}"
        echo -e "  ${YELLOW}Details: $details${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 1: Verify iptables default policies
echo "Test 1: Checking iptables default policies..."
OUTPUT=$(exec_container iptables -L -n | head -10)
if echo "$OUTPUT" | grep -q "Chain INPUT (policy DROP)" && \
   echo "$OUTPUT" | grep -q "Chain FORWARD (policy DROP)" && \
   echo "$OUTPUT" | grep -q "Chain OUTPUT (policy DROP)"; then
    print_result "Default DROP policies" "PASS"
else
    print_result "Default DROP policies" "FAIL" "Not all chains have DROP policy"
fi

# Test 2: Check DNS leak prevention rules
echo ""
echo "Test 2: Checking DNS leak prevention..."
DNS_BLOCK=$(exec_container iptables -L OUTPUT -n -v | grep -E "dpt:53.*DROP.*eth0" | wc -l)
DNS_ALLOW=$(exec_container iptables -L OUTPUT -n -v | grep -E "dpt:53.*ACCEPT.*(tun0|wg)" | wc -l)
if [ "$DNS_BLOCK" -gt 0 ] && [ "$DNS_ALLOW" -gt 0 ]; then
    print_result "DNS leak prevention" "PASS"
else
    print_result "DNS leak prevention" "FAIL" "DNS rules not properly configured"
fi

# Test 3: Verify VPN interface exists and is up
echo ""
echo "Test 3: Checking VPN interface status..."
VPN_INTERFACE=$(exec_container cat /tmp/vpn_interface_name 2>/dev/null || echo "tun0")
if exec_container ip link show "$VPN_INTERFACE" &>/dev/null; then
    if exec_container ip link show "$VPN_INTERFACE" | grep -q "state UP"; then
        VPN_IP=$(exec_container ip addr show "$VPN_INTERFACE" | grep "inet " | awk '{print $2}')
        print_result "VPN interface active" "PASS"
        echo "  VPN IP: $VPN_IP"
    else
        print_result "VPN interface active" "FAIL" "Interface exists but is DOWN"
    fi
else
    print_result "VPN interface active" "FAIL" "Interface $VPN_INTERFACE not found"
fi

# Test 4: Check VPN monitoring service
echo ""
echo "Test 4: Checking VPN monitoring service..."
if exec_container s6-svstat /var/run/s6/services/vpn-monitor 2>/dev/null | grep -q "up"; then
    print_result "VPN monitor service" "PASS"
else
    print_result "VPN monitor service" "FAIL" "Service not running"
fi

# Test 5: Test outbound connectivity through VPN only
echo ""
echo "Test 5: Testing outbound connectivity..."
# Try to ping through VPN interface
if exec_container ping -c 1 -W 2 -I "$VPN_INTERFACE" 1.1.1.1 &>/dev/null; then
    print_result "VPN connectivity" "PASS"
else
    print_result "VPN connectivity" "WARN" "Cannot reach internet through VPN"
fi

# Test 6: Verify eth0 blocks non-allowed traffic
echo ""
echo "Test 6: Checking eth0 restrictions..."
ETH0_DROP_RULE=$(exec_container iptables -L OUTPUT -n | grep -E "DROP.*eth0" | wc -l)
if [ "$ETH0_DROP_RULE" -gt 0 ]; then
    print_result "eth0 traffic blocking" "PASS"
else
    print_result "eth0 traffic blocking" "FAIL" "No DROP rule for eth0"
fi

# Test 7: Simulate VPN failure and check if NZBGet stops
echo ""
echo "Test 7: Simulating VPN failure (this may take up to 90 seconds)..."
echo "  Stopping VPN interface..."

# Save current state
NZBGET_RUNNING_BEFORE=$(exec_container pgrep nzbget | wc -l)

# Bring down VPN interface
exec_container ip link set "$VPN_INTERFACE" down 2>/dev/null || true

# Wait for monitoring to detect failure (based on VPN_CHECK_INTERVAL and VPN_MAX_FAILURES)
echo "  Waiting for monitor to detect failure..."
sleep 100

# Check if NZBGet was stopped
NZBGET_RUNNING_AFTER=$(exec_container pgrep nzbget | wc -l)
VPN_FAIL_FLAG=$(exec_container ls /tmp/vpn_failed_nzbget_stopped 2>/dev/null | wc -l)

if [ "$NZBGET_RUNNING_AFTER" -eq 0 ] && [ "$VPN_FAIL_FLAG" -eq 1 ]; then
    print_result "Auto-stop on VPN failure" "PASS"
else
    print_result "Auto-stop on VPN failure" "FAIL" "NZBGet still running or flag not set"
fi

# Restore VPN interface
echo "  Restoring VPN interface..."
exec_container ip link set "$VPN_INTERFACE" up 2>/dev/null || true

# Test 8: Check for packet leaks with tcpdump (if available)
echo ""
echo "Test 8: Checking for packet leaks on eth0..."
if exec_container which tcpdump &>/dev/null; then
    # Start tcpdump in background
    exec_container timeout 5 tcpdump -i eth0 -c 10 'not port 6789 and not port 8080 and not arp' 2>/dev/null > /tmp/tcpdump_out &
    TCPDUMP_PID=$!

    # Generate some traffic
    exec_container curl -s --max-time 3 http://example.com &>/dev/null || true

    # Wait for tcpdump
    wait $TCPDUMP_PID 2>/dev/null || true

    # Check if any packets were captured
    LEAKED_PACKETS=$(wc -l < /tmp/tcpdump_out)
    if [ "$LEAKED_PACKETS" -lt 2 ]; then
        print_result "Packet leak test" "PASS"
    else
        print_result "Packet leak test" "FAIL" "Detected $LEAKED_PACKETS packets on eth0"
    fi
    rm -f /tmp/tcpdump_out
else
    echo "  Skipping (tcpdump not available)"
fi

# Test 9: DNS resolution test
echo ""
echo "Test 9: Testing DNS resolution..."
# DNS should fail on eth0 but work through VPN
if exec_container nslookup google.com 2>/dev/null | grep -q "Address:"; then
    print_result "DNS through VPN" "PASS"
else
    print_result "DNS through VPN" "FAIL" "DNS resolution not working"
fi

# Test 10: Check monitoring alerts log
echo ""
echo "Test 10: Checking monitoring alerts..."
if exec_container test -f /tmp/vpn_monitor_alerts.log; then
    ALERT_COUNT=$(exec_container wc -l < /tmp/vpn_monitor_alerts.log)
    print_result "Alert logging" "PASS"
    echo "  Found $ALERT_COUNT alerts in log"
else
    print_result "Alert logging" "WARN" "No alert log found"
fi

# Summary
echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed! Kill switch is working properly.${NC}"
    exit 0
else
    echo -e "${YELLOW}Some tests failed. Review the configuration.${NC}"

    # Provide debugging info if verbose
    if [ "$VERBOSE" = "true" ]; then
        echo ""
        echo "Debug Information:"
        echo "=================="
        echo "IPTables Rules:"
        exec_container iptables -L -n -v | head -30
        echo ""
        echo "VPN Monitor Log (last 20 lines):"
        exec_container tail -20 /tmp/vpn-monitor.log 2>/dev/null || echo "Log not found"
    fi
    exit 1
fi