#!/command/with-contenv bash
# VPN Monitor Service - Continuously monitors VPN health and enforces killswitch
# Stops NZBGet immediately if VPN connection fails

set -e

echo "[VPN-MONITOR] Starting VPN monitoring service..."
date

# Configuration
CHECK_INTERVAL=${VPN_CHECK_INTERVAL:-30}  # Check every 30 seconds by default
MAX_FAILURES=${VPN_MAX_FAILURES:-3}       # Allow 3 consecutive failures before action
FAILURE_COUNT=0
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"

# Get VPN interface
if [ -f "$VPN_INTERFACE_FILE" ]; then
    VPN_INTERFACE=$(cat "$VPN_INTERFACE_FILE")
else
    if [ "${VPN_CLIENT,,}" = "wireguard" ]; then
        VPN_INTERFACE="wg0"
    else
        VPN_INTERFACE="tun0"
    fi
fi

echo "[VPN-MONITOR] Monitoring VPN interface: $VPN_INTERFACE"
echo "[VPN-MONITOR] Check interval: ${CHECK_INTERVAL}s"
echo "[VPN-MONITOR] Max failures before action: $MAX_FAILURES"

# Function to check VPN connectivity
check_vpn_connection() {
    local vpn_ok=1

    # Check 1: Interface exists
    if ! ip link show "$VPN_INTERFACE" &>/dev/null; then
        echo "[VPN-MONITOR] ERROR: VPN interface $VPN_INTERFACE does not exist!"
        return 1
    fi

    # Check 2: Interface is UP
    if ! ip link show "$VPN_INTERFACE" | grep -q "state UP"; then
        echo "[VPN-MONITOR] ERROR: VPN interface $VPN_INTERFACE is not UP!"
        return 1
    fi

    # Check 3: Interface has IP address
    if ! ip addr show "$VPN_INTERFACE" | grep -q "inet "; then
        echo "[VPN-MONITOR] ERROR: VPN interface $VPN_INTERFACE has no IP address!"
        return 1
    fi

    # Check 4: Routing table has VPN routes
    if ! ip route | grep -q "dev $VPN_INTERFACE"; then
        echo "[VPN-MONITOR] ERROR: No routes through VPN interface $VPN_INTERFACE!"
        return 1
    fi

    # Check 5: DNS resolution through VPN (optional but recommended)
    if [ "${CHECK_DNS,,}" = "true" ]; then
        # Test DNS resolution - use a reliable public DNS test
        if ! nslookup google.com 1.1.1.1 &>/dev/null; then
            echo "[VPN-MONITOR] WARNING: DNS resolution test failed"
            # This is a warning, not a failure - DNS might be temporarily slow
        fi
    fi

    # Check 6: External IP check (optional, requires curl)
    if [ "${CHECK_EXTERNAL_IP,,}" = "true" ] && command -v curl &>/dev/null; then
        EXTERNAL_IP=$(curl -s --max-time 10 --interface "$VPN_INTERFACE" https://api.ipify.org 2>/dev/null)
        if [ -n "$EXTERNAL_IP" ]; then
            echo "[VPN-MONITOR] External IP through VPN: $EXTERNAL_IP"
        else
            echo "[VPN-MONITOR] WARNING: Could not determine external IP"
        fi
    fi

    return 0
}

# Function to stop NZBGet
stop_nzbget() {
    echo "[VPN-MONITOR] CRITICAL: Stopping NZBGet due to VPN failure!"

    # Stop NZBGet service via s6
    if [ -d /var/run/s6/services/nzbget ]; then
        s6-svc -d /var/run/s6/services/nzbget
        echo "[VPN-MONITOR] NZBGet service stopped via s6"
    fi

    # Double-check by killing process directly
    if pgrep -x "nzbget" > /dev/null; then
        pkill -TERM nzbget
        sleep 2
        if pgrep -x "nzbget" > /dev/null; then
            pkill -KILL nzbget
            echo "[VPN-MONITOR] NZBGet process forcefully terminated"
        fi
    fi

    # Create a flag file to prevent restart
    touch /tmp/vpn_failed_nzbget_stopped
    echo "[VPN-MONITOR] Created flag file to prevent NZBGet restart"
}

# Function to restart NZBGet if VPN is restored
restart_nzbget() {
    if [ -f /tmp/vpn_failed_nzbget_stopped ]; then
        echo "[VPN-MONITOR] VPN restored, restarting NZBGet..."
        rm -f /tmp/vpn_failed_nzbget_stopped

        # Restart NZBGet service via s6
        if [ -d /var/run/s6/services/nzbget ]; then
            s6-svc -u /var/run/s6/services/nzbget
            echo "[VPN-MONITOR] NZBGet service restarted via s6"
        fi
    fi
}

# Function to enforce strict iptables killswitch
enforce_killswitch() {
    echo "[VPN-MONITOR] Enforcing strict killswitch rules..."

    # Set OUTPUT policy to DROP to block all outgoing traffic
    iptables -P OUTPUT DROP

    # Only allow essential local traffic
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established connections to finish
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Block all new outgoing connections on eth0
    iptables -A OUTPUT -o eth0 -m state --state NEW -j DROP

    echo "[VPN-MONITOR] Killswitch enforced - all new outgoing traffic blocked"
}

# Function to send alert (can be extended for notifications)
send_alert() {
    local message="$1"
    echo "[VPN-MONITOR] ALERT: $message"

    # Log to system log if available
    if command -v logger &>/dev/null; then
        logger -t "vpn-monitor" -p user.crit "$message"
    fi

    # Create alert file for external monitoring
    echo "$(date): $message" >> /tmp/vpn_monitor_alerts.log
}

# Main monitoring loop
echo "[VPN-MONITOR] Starting monitoring loop..."

while true; do
    if check_vpn_connection; then
        # VPN is healthy
        if [ $FAILURE_COUNT -gt 0 ]; then
            echo "[VPN-MONITOR] VPN connection restored"
            send_alert "VPN connection restored after $FAILURE_COUNT failures"
            FAILURE_COUNT=0
            restart_nzbget
        fi
        echo "[VPN-MONITOR] VPN healthy at $(date)"
    else
        # VPN check failed
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        echo "[VPN-MONITOR] VPN check failed! Failure count: $FAILURE_COUNT/$MAX_FAILURES"
        send_alert "VPN check failed! Count: $FAILURE_COUNT/$MAX_FAILURES"

        if [ $FAILURE_COUNT -ge $MAX_FAILURES ]; then
            echo "[VPN-MONITOR] CRITICAL: Maximum VPN failures reached!"
            send_alert "Maximum VPN failures reached - stopping NZBGet and enforcing killswitch"

            # Take protective actions
            stop_nzbget
            enforce_killswitch

            # Optional: Try to restart VPN (implementation depends on VPN client)
            if [ "${AUTO_RESTART_VPN,,}" = "true" ]; then
                echo "[VPN-MONITOR] Attempting to restart VPN..."
                if [ "${VPN_CLIENT,,}" = "openvpn" ]; then
                    s6-svc -r /var/run/s6/services/openvpn
                elif [ "${VPN_CLIENT,,}" = "wireguard" ]; then
                    wg-quick down "$VPN_INTERFACE" 2>/dev/null || true
                    sleep 2
                    wg-quick up "$VPN_INTERFACE" 2>/dev/null || true
                fi
            fi
        fi
    fi

    sleep "$CHECK_INTERVAL"
done