#!/command/with-contenv bash
# Enhanced VPN Kill Switch with strict security policies
# This script implements comprehensive network security to prevent data leaks

set -e
set -x

echo "[KILLSWITCH] Starting enhanced VPN kill switch setup..."
date

# Log to file for debugging
exec &> /tmp/vpn-killswitch.log
exec > >(tee -a /tmp/vpn-killswitch.log) 2> >(tee -a /tmp/vpn-killswitch.log >&2)

# Get VPN interface
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"
if [ -f "$VPN_INTERFACE_FILE" ]; then
    VPN_INTERFACE=$(cat "$VPN_INTERFACE_FILE")
else
    # Default based on VPN client type
    if [ "${VPN_CLIENT,,}" = "wireguard" ]; then
        VPN_INTERFACE="wg0"
    else
        VPN_INTERFACE="tun0"
    fi
fi

echo "[KILLSWITCH] VPN Interface: $VPN_INTERFACE"

# Get eth0 gateway and IP
ETH0_GATEWAY=$(ip route | grep default | grep eth0 | awk '{print $3}')
ETH0_IP=$(ip -4 addr show dev eth0 | awk '/inet/ {print $2}' | cut -d/ -f1)

echo "[KILLSWITCH] ETH0 Gateway: $ETH0_GATEWAY"
echo "[KILLSWITCH] ETH0 IP: $ETH0_IP"

# Function to apply strict iptables rules
apply_strict_iptables() {
    echo "[KILLSWITCH] Applying strict iptables rules with default DROP policy..."

    # Flush all existing rules first
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -X

    # Set default policies to DROP (strict deny-all)
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

    echo "[KILLSWITCH] Default policies set to DROP on all chains"

    # Allow loopback (essential for local communication)
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established connections (critical for existing connections)
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # DNS Leak Prevention - Block all DNS except through VPN
    echo "[KILLSWITCH] Implementing DNS leak prevention..."

    # Block DNS queries on eth0 (port 53 UDP/TCP)
    iptables -A OUTPUT -o eth0 -p udp --dport 53 -j DROP
    iptables -A OUTPUT -o eth0 -p tcp --dport 53 -j DROP

    # Only allow DNS through VPN interface
    iptables -A OUTPUT -o "$VPN_INTERFACE" -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -o "$VPN_INTERFACE" -p tcp --dport 53 -j ACCEPT

    echo "[KILLSWITCH] DNS leak prevention rules applied"

    # Allow NZBGet UI access (local only)
    iptables -A INPUT -i eth0 -p tcp --dport 6789 -j ACCEPT

    # Allow monitoring port
    iptables -A INPUT -i eth0 -p tcp --dport 8080 -j ACCEPT

    # VPN Connection Rules
    if [ "${VPN_CLIENT,,}" = "openvpn" ]; then
        echo "[KILLSWITCH] Adding OpenVPN connection rules..."
        # Allow OpenVPN connection establishment
        iptables -A OUTPUT -o eth0 -p udp --dport 1194 -j ACCEPT
        iptables -A OUTPUT -o eth0 -p tcp --dport 443 -j ACCEPT
        iptables -A OUTPUT -o eth0 -p tcp --dport 1194 -j ACCEPT

        # Extract and allow specific VPN server if config exists
        if [ -f "/tmp/config.ovpn" ]; then
            VPN_SERVERS=$(grep -E "^remote " /tmp/config.ovpn | awk '{print $2}')
            for server in $VPN_SERVERS; do
                # Resolve to IP if hostname
                if ! echo "$server" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                    server_ip=$(nslookup "$server" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
                    if [ -n "$server_ip" ]; then
                        echo "[KILLSWITCH] Allowing VPN server: $server_ip"
                        iptables -A OUTPUT -o eth0 -d "$server_ip" -j ACCEPT
                    fi
                else
                    echo "[KILLSWITCH] Allowing VPN server: $server"
                    iptables -A OUTPUT -o eth0 -d "$server" -j ACCEPT
                fi
            done
        fi
    elif [ "${VPN_CLIENT,,}" = "wireguard" ]; then
        echo "[KILLSWITCH] Adding WireGuard connection rules..."
        # Allow WireGuard connection
        iptables -A OUTPUT -o eth0 -p udp --dport 51820 -j ACCEPT

        # Extract endpoint from WireGuard config if available
        WG_CONFIG=$(find /config/wireguard -maxdepth 1 -name '*.conf' -print -quit)
        if [ -n "$WG_CONFIG" ] && [ -f "$WG_CONFIG" ]; then
            WG_ENDPOINTS=$(grep -E "^Endpoint" "$WG_CONFIG" | awk -F'=' '{print $2}' | awk -F':' '{print $1}' | tr -d ' ')
            for endpoint in $WG_ENDPOINTS; do
                if [ -n "$endpoint" ]; then
                    echo "[KILLSWITCH] Allowing WireGuard endpoint: $endpoint"
                    iptables -A OUTPUT -o eth0 -d "$endpoint" -j ACCEPT
                fi
            done
        fi
    fi

    # LAN access (if configured)
    if [ -n "$LAN_NETWORK" ]; then
        echo "[KILLSWITCH] Allowing LAN network: $LAN_NETWORK"
        iptables -A OUTPUT -o eth0 -d "$LAN_NETWORK" -j ACCEPT
        iptables -A INPUT -i eth0 -s "$LAN_NETWORK" -j ACCEPT
    fi

    # Policy-based routing for UI access
    echo "[KILLSWITCH] Setting up policy-based routing for UI access..."

    # Mark connections to NZBGet UI
    if [ -n "$ETH0_IP" ]; then
        iptables -t mangle -A PREROUTING -d "$ETH0_IP" -p tcp --dport 6789 -j CONNMARK --set-mark 0x1
        iptables -t mangle -A PREROUTING -d "$ETH0_IP" -p tcp --dport 8080 -j CONNMARK --set-mark 0x1
    fi

    # Restore mark for response packets
    iptables -t mangle -A OUTPUT -p tcp --sport 6789 -j CONNMARK --restore-mark
    iptables -t mangle -A OUTPUT -p tcp --sport 8080 -j CONNMARK --restore-mark

    # Create routing table for marked packets
    ip rule add fwmark 0x1 lookup 100 priority 1000 2>/dev/null || true
    ip route add default via "$ETH0_GATEWAY" dev eth0 table 100 2>/dev/null || true

    # Allow all traffic through VPN interface
    iptables -A OUTPUT -o "$VPN_INTERFACE" -j ACCEPT

    # Log dropped packets (optional, can be verbose)
    if [ "${DEBUG,,}" = "true" ]; then
        iptables -A OUTPUT -j LOG --log-prefix "[KILLSWITCH-DROP] " --log-level 4
    fi

    echo "[KILLSWITCH] Strict iptables rules applied successfully"
}

# Function to verify VPN is active
check_vpn_status() {
    # Check if VPN interface exists and is UP
    if ip link show "$VPN_INTERFACE" &>/dev/null; then
        if ip link show "$VPN_INTERFACE" | grep -q "state UP"; then
            # Check if interface has an IP
            if ip addr show "$VPN_INTERFACE" | grep -q "inet "; then
                return 0
            fi
        fi
    fi
    return 1
}

# Apply the strict rules
apply_strict_iptables

# Verify killswitch is active
echo "[KILLSWITCH] Verifying kill switch is active..."
iptables -L -n -v | head -20

# Create completion flag
touch /tmp/vpn_killswitch_active
echo "[KILLSWITCH] Enhanced VPN kill switch activated at $(date)"

exit 0