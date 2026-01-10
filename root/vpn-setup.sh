#!/command/with-contenv bash
# shellcheck shell=bash
# This script sets up the VPN connection (OpenVPN or WireGuard)
# and configures iptables for policy-based routing.

set -e # Exit immediately if a command exits with a non-zero status.
# set -x # Uncomment for debugging

echo "[INFO] Starting VPN setup script..."
date

# Ensure /tmp exists and is writable
mkdir -p /tmp
chmod 777 /tmp

# Log all output of this script to a file in /tmp for easier debugging via docker exec
exec &> /tmp/vpn-setup.log
# Also print to stdout/stderr for s6 logging
exec > >(tee -a /tmp/vpn-setup.log) 2> >(tee -a /tmp/vpn-setup.log >&2)


if [ "${DEBUG,,}" = "true" ]; then
  echo "[DEBUG] Debug mode enabled. Full script output will be logged."
  set -x
fi

# Default VPN Interface (will be updated after connection)
VPN_INTERFACE_FILE="/tmp/vpn_interface_name"
DEFAULT_VPN_INTERFACE="tun0" # Common for OpenVPN
if [ "${VPN_CLIENT,,}" = "wireguard" ]; then
  # For WireGuard, derive from VPN_CONFIG or default to wg0
  if [ -n "$VPN_CONFIG" ]; then # Using VPN_CONFIG now
    DEFAULT_VPN_INTERFACE=$(basename "$VPN_CONFIG" .conf)
  else # try to find a .conf file
    WG_CONF_FOUND=$(find /config/wireguard -maxdepth 1 -name '*.conf' -print -quit)
    if [ -n "$WG_CONF_FOUND" ]; then
        DEFAULT_VPN_INTERFACE=$(basename "$WG_CONF_FOUND" .conf)
    else
        DEFAULT_VPN_INTERFACE="wg0" # Fallback if no specific config found
    fi
  fi
fi
echo "$DEFAULT_VPN_INTERFACE" > "$VPN_INTERFACE_FILE"
echo "[INFO] Default VPN interface set to: $(cat $VPN_INTERFACE_FILE)"


# Function to find OpenVPN credentials
find_vpn_credentials() {
  # Clear any stale credentials file
  rm -f /tmp/vpn-credentials

  # Priority 1: VPN_USER and VPN_PASS from environment.
  if [ -n "$VPN_USER" ] && [ -n "$VPN_PASS" ]; then
    echo "[INFO] Using VPN_USER and VPN_PASS from environment."
    echo "$VPN_USER" > /tmp/vpn-credentials
    echo "$VPN_PASS" >> /tmp/vpn-credentials
    if [ -s /tmp/vpn-credentials ] && [ "$(wc -l < /tmp/vpn-credentials)" -ge 2 ]; then
        echo "[INFO] Credentials successfully written to /tmp/vpn-credentials from environment variables."
        return 0
    else
        echo "[WARN] VPN_USER and/or VPN_PASS were provided but resulted in an empty or incomplete credential file. Clearing."
        rm -f /tmp/vpn-credentials
    fi
  fi

  # Priority 2: Check for credentials file (try both common names)
  for CRED_FILE in "/config/openvpn/credentials.txt" "/config/openvpn/credentials.conf"; do
    if [ -f "$CRED_FILE" ] && [ -r "$CRED_FILE" ]; then
      FIXED_CRED_PATH="$CRED_FILE"
      break
    fi
  done
  
  if [ -n "$FIXED_CRED_PATH" ]; then
    echo "[INFO] Checking for credentials file at fixed path: $FIXED_CRED_PATH"
    # Ensure the file is not empty and has at least two lines (user & pass)
    if [ -s "$FIXED_CRED_PATH" ] && [ "$(wc -l < "$FIXED_CRED_PATH")" -ge 2 ]; then
      echo "[INFO] Using OpenVPN credentials from $FIXED_CRED_PATH."
      cp "$FIXED_CRED_PATH" /tmp/vpn-credentials
      # Double check copy success and content
      if [ -s /tmp/vpn-credentials ] && [ "$(wc -l < /tmp/vpn-credentials)" -ge 2 ]; then
        echo "[INFO] Credentials successfully copied to /tmp/vpn-credentials from $FIXED_CRED_PATH."
        return 0
      else
        echo "[WARN] Failed to copy or validate credentials from $FIXED_CRED_PATH to /tmp/vpn-credentials. Clearing."
        rm -f /tmp/vpn-credentials
      fi
    else
      echo "[WARN] Credentials file $FIXED_CRED_PATH was found but is empty or does not contain at least two lines. Ignoring."
    fi
  else
    echo "[INFO] No credentials file found at /config/openvpn/credentials.txt or /config/openvpn/credentials.conf (this is okay if using VPN_USER/PASS or if your VPN config doesn't need separate auth)."
  fi
  
  # If neither method yielded credentials
  echo "[WARN] No valid VPN credentials provided via VPN_USER/VPN_PASS or credentials file."
  echo "[INFO] If your OpenVPN configuration requires username/password authentication and doesn't embed them, connection may fail."
  return 1 
}

# Function to start OpenVPN
start_openvpn() {
  echo "[INFO] Setting up OpenVPN..."
  OVPN_CONFIG_FILE=""
  if [ -n "$VPN_CONFIG" ]; then
    if [ -f "$VPN_CONFIG" ]; then
      OVPN_CONFIG_FILE="$VPN_CONFIG"
      echo "[INFO] Using OpenVPN config: $OVPN_CONFIG_FILE"
    else
      echo "[ERROR] Specified VPN_CONFIG=$VPN_CONFIG not found."
      exit 1
    fi
  else
    # Try to find the first .ovpn file in /config/openvpn
    OVPN_CONFIG_FILE=$(find /config/openvpn -maxdepth 1 -name '*.ovpn' -print -quit)
    if [ -z "$OVPN_CONFIG_FILE" ]; then
      echo "[ERROR] No OpenVPN configuration file specified via VPN_CONFIG and none found in /config/openvpn."
      exit 1
    else
      echo "[INFO] Automatically selected OpenVPN config: $OVPN_CONFIG_FILE"
    fi
  fi

  # Credentials
  if ! find_vpn_credentials; then
    echo "[ERROR] OpenVPN credentials not provided or found. Please set VPN_USER/VPN_PASS environment variables, or create a credentials file at /config/openvpn/credentials.txt (username on line 1, password on line 2)."
    exit 1
  fi

  # Create up/down scripts for OpenVPN
  mkdir -p /etc/openvpn
  cat << EOF > /etc/openvpn/update-resolv.sh
#!/bin/bash
# Script to update resolv.conf with DNS servers from OpenVPN
# exec &> /tmp/openvpn_script.log # DO NOT log here, it causes issues with OpenVPN execution context
# Instead, log to /tmp/openvpn.log directly in this script

set -x # For debugging individual commands in this script

echo "--- OpenVPN UP script started ---" | tee -a /tmp/openvpn.log
date | tee -a /tmp/openvpn.log
# env | tee -a /tmp/openvpn.log # Log environment to see what OpenVPN provides

# Backup original resolv.conf if not already backed up
if [ ! -f "/tmp/resolv.conf.backup" ]; then
  if [ -f "/etc/resolv.conf" ]; then # Only backup if original exists
    cp "/etc/resolv.conf" "/tmp/resolv.conf.backup"
    echo "Backed up /etc/resolv.conf to /tmp/resolv.conf.backup" | tee -a /tmp/openvpn.log
  else
    echo "Original /etc/resolv.conf not found, cannot backup." | tee -a /tmp/openvpn.log
  fi
fi

# Start with an empty temp resolv.conf
echo "# Generated by OpenVPN update-resolv.sh" > "/tmp/resolv.conf.openvpn"

# Option 1: Use NAME_SERVERS if provided from parent environment
# The 'foreign_option' parsing relies on these being exported to the script by OpenVPN
# Ensure NAME_SERVERS is accessible here if set in Docker env.
# openvpn --script-security 2 --up /etc/openvpn/update-resolv.sh --up-restart
# needs NAME_SERVERS to be pushed or available in the script's env.
# If using with-contenv, NAME_SERVERS should be available.

if [ -n "\$NAME_SERVERS" ]; then
  echo "[INFO] Using NAME_SERVERS: \$NAME_SERVERS" | tee -a /tmp/openvpn.log
  # Use sed to transform comma-separated list directly to nameserver lines
  echo "\$NAME_SERVERS" | sed -e 's/,/\nnameserver /g' -e 's/^/nameserver /' >> "/tmp/resolv.conf.openvpn"
else
  # Option 2: Try to parse foreign_option_ variables for DNS (pushed by VPN server)
  echo "[INFO] NAME_SERVERS not set, trying to use DNS from VPN (foreign_option_X)" | tee -a /tmp/openvpn.log
  dns_found=0
  for option_var_name in \$(env | grep '^foreign_option_' | cut -d= -f1); do
    option_var_value=\$(eval echo "\\\"\$\$option_var_name\\\"")
    if echo "\$option_var_value" | grep -q '^dhcp-option DNS'; then
      dns_server=\$(echo "\$option_var_value" | cut -d' ' -f3)
      echo "nameserver \$dns_server" >> "/tmp/resolv.conf.openvpn"
      echo "[INFO] Added DNS server from VPN: \$dns_server" | tee -a /tmp/openvpn.log
      dns_found=1
    fi
  done
  if [ \$dns_found -eq 0 ]; then
      echo "[WARN] No DNS servers pushed by VPN, and NAME_SERVERS not set. Using fallbacks." | tee -a /tmp/openvpn.log
      echo "nameserver 1.1.1.1" >> "/tmp/resolv.conf.openvpn" # Cloudflare
      echo "nameserver 8.8.8.8" >> "/tmp/resolv.conf.openvpn" # Google
  fi
fi

# Atomically replace resolv.conf
# Check if /tmp/resolv.conf.openvpn has content beyond the initial comment
if [ \$(grep -cv '^#' /tmp/resolv.conf.openvpn) -gt 0 ]; then
  cp "/tmp/resolv.conf.openvpn" "/etc/resolv.conf"
  echo "Updated /etc/resolv.conf" | tee -a /tmp/openvpn.log
else
  echo "[WARN] /tmp/resolv.conf.openvpn was empty or only comments. Not updating /etc/resolv.conf." | tee -a /tmp/openvpn.log
fi

# Create a flag file to indicate the 'up' script has completed
# This helps the main vpn-setup.sh script to know when tun0 is likely configured
echo "OpenVPN UP script completed. Interface: \$dev" > /tmp/openvpn_up_complete
echo "[INFO] OpenVPN UP script for \$dev completed (flag file created)." | tee -a /tmp/openvpn.log
exit 0
EOF

  cat << EOF > /etc/openvpn/restore-resolv.sh
#!/bin/bash
# Script to restore original resolv.conf
# exec &> /tmp/openvpn_script_down.log # DO NOT log here
set -x
echo "--- OpenVPN DOWN script started ---" | tee -a /tmp/openvpn.log
date | tee -a /tmp/openvpn.log

if [ -f "/tmp/resolv.conf.backup" ]; then
  cp "/tmp/resolv.conf.backup" "/etc/resolv.conf"
  echo "Restored /etc/resolv.conf from /tmp/resolv.conf.backup" | tee -a /tmp/openvpn.log
  rm "/tmp/resolv.conf.backup" # Clean up backup
else
  echo "No backup /tmp/resolv.conf.backup found to restore." | tee -a /tmp/openvpn.log
fi
# Remove the flag file
rm -f /tmp/openvpn_up_complete
echo "[INFO] OpenVPN DOWN script for \$dev completed (flag file removed)." | tee -a /tmp/openvpn.log
exit 0
EOF

  chmod +x /etc/openvpn/update-resolv.sh /etc/openvpn/restore-resolv.sh

  # Modify OVPN config on the fly for auth-user-pass and script security
  TEMP_OVPN_CONFIG="/tmp/config.ovpn"
  cp "$OVPN_CONFIG_FILE" "$TEMP_OVPN_CONFIG"
  
  # Ensure the config file ends with a newline to prevent formatting issues
  # Add newline if the file doesn't end with one
  sed -i -e '$a\' "$TEMP_OVPN_CONFIG"
  # Alternative fix: explicitly add newline before our additions
  printf '\n' >> "$TEMP_OVPN_CONFIG"
  
  # Ensure auth-user-pass points to our standard credentials file
  if grep -q "^auth-user-pass" "$TEMP_OVPN_CONFIG"; then
    sed -i 's|^auth-user-pass.*|auth-user-pass /tmp/vpn-credentials|' "$TEMP_OVPN_CONFIG"
  else
    echo "auth-user-pass /tmp/vpn-credentials" >> "$TEMP_OVPN_CONFIG"
  fi
  # Ensure script-security 2 is set for up/down scripts
  if grep -q "^script-security" "$TEMP_OVPN_CONFIG"; then
    sed -i 's|^script-security.*|script-security 2|' "$TEMP_OVPN_CONFIG"
  else
    echo "script-security 2" >> "$TEMP_OVPN_CONFIG"
  fi
  # Add up and down script directives
  if ! grep -q "^up " "$TEMP_OVPN_CONFIG"; then
    echo "up /etc/openvpn/update-resolv.sh" >> "$TEMP_OVPN_CONFIG"
  fi
  if ! grep -q "^down " "$TEMP_OVPN_CONFIG"; then
    echo "down /etc/openvpn/restore-resolv.sh" >> "$TEMP_OVPN_CONFIG"
  fi
  # Remove redirect-gateway if LAN_NETWORK is set, we'll handle routing
  if [ -n "$LAN_NETWORK" ]; then
    sed -i '/^redirect-gateway def1/d' "$TEMP_OVPN_CONFIG"
    echo "[INFO] Removed redirect-gateway def1 from OpenVPN config due to LAN_NETWORK being set."
  fi


  echo "[INFO] OpenVPN configuration prepared. Service will be started by s6-overlay."
  echo "[INFO] Configuration file: $TEMP_OVPN_CONFIG"
  echo "[INFO] VPN interface: $(cat $VPN_INTERFACE_FILE)"

}

# Function to start WireGuard
start_wireguard() {
  echo "[INFO] Setting up WireGuard..."
  WG_CONFIG="" # This will be the path to the actual config file
  if [ -n "$VPN_CONFIG" ]; then # Using VPN_CONFIG now
      if [ -f "$VPN_CONFIG" ]; then
          WG_CONFIG="$VPN_CONFIG"
          echo "[INFO] Using WireGuard config: $WG_CONFIG"
      else
          echo "[ERROR] Specified VPN_CONFIG (for WireGuard) = $VPN_CONFIG not found."
          exit 1
      fi
  else
      # Try to find the first .conf file in /config/wireguard
      WG_CONF_FOUND=$(find /config/wireguard -maxdepth 1 -name '*.conf' -print -quit)
      if [ -z "$WG_CONF_FOUND" ]; then
          echo "[ERROR] No WireGuard configuration file specified via VPN_CONFIG and none found in /config/wireguard."
          exit 1
      else
          WG_CONFIG="$WG_CONF_FOUND"
          echo "[INFO] Automatically selected WireGuard config: $WG_CONFIG"
          # Update VPN_INTERFACE_FILE based on found config, if VPN_CONFIG was not explicitly set
          echo "$(basename "$WG_CONFIG" .conf)" > "$VPN_INTERFACE_FILE"
      fi
  fi
  INTERFACE_NAME=$(cat "$VPN_INTERFACE_FILE")

  # Log config details for debugging (without private key)
  echo "[INFO] WireGuard config contents (sanitized):"
  grep -v "PrivateKey" "$WG_CONFIG" | head -20

  echo "[INFO] Starting WireGuard for interface $INTERFACE_NAME using $WG_CONFIG..."

  # Run wg-quick with verbose output
  if ! wg-quick up "$WG_CONFIG" 2>&1; then
    echo "[ERROR] wg-quick up failed. Check config file and permissions."
    echo "[DEBUG] Attempting to show wg-quick error details..."
    # Try to bring down first in case partial setup
    wg-quick down "$WG_CONFIG" 2>/dev/null || true
    # Retry with more verbose output
    WG_QUICK_OUT=$(wg-quick up "$WG_CONFIG" 2>&1) || true
    echo "[DEBUG] wg-quick output: $WG_QUICK_OUT"
  fi

  # Verify interface is up
  sleep 2
  if ip link show "$INTERFACE_NAME" >/dev/null 2>&1; then
    echo "[INFO] WireGuard interface $INTERFACE_NAME exists"
    ip link show "$INTERFACE_NAME"

    # Check if interface has an IP
    WG_IP=$(ip -4 addr show "$INTERFACE_NAME" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ -n "$WG_IP" ]; then
      echo "[INFO] WireGuard interface has IP: $WG_IP"
    else
      echo "[WARN] WireGuard interface has no IPv4 address assigned"
    fi

    # Show WireGuard status
    echo "[INFO] WireGuard status:"
    wg show "$INTERFACE_NAME" 2>/dev/null || echo "[WARN] Could not get wg show output"
  else
    echo "[ERROR] WireGuard interface $INTERFACE_NAME does not exist after wg-quick up"
    echo "[DEBUG] Available interfaces:"
    ip link show
  fi

  echo "[INFO] WireGuard started. Interface: $INTERFACE_NAME"
  # For WireGuard, DNS is typically set in the .conf file's [Interface] section (DNS = x.x.x.x)
  # wg-quick should handle setting this up.
  # If NAME_SERVERS is provided, we can override /etc/resolv.conf
  if [ -n "$NAME_SERVERS" ]; then
    echo "[INFO] NAME_SERVERS is set ($NAME_SERVERS), updating /etc/resolv.conf for WireGuard."
    # Backup original resolv.conf if not already backed up
    if [ ! -f "/tmp/resolv.conf.backup" ]; then
      if [ -f "/etc/resolv.conf" ]; then cp "/etc/resolv.conf" "/tmp/resolv.conf.backup"; fi
    fi
    echo "# Generated by vpn-setup.sh for WireGuard using NAME_SERVERS" > /tmp/resolv.conf.wireguard
    echo "$NAME_SERVERS" | sed -e 's/,/\nnameserver /g' -e 's/^/nameserver /' >> "/tmp/resolv.conf.wireguard"
    cp "/tmp/resolv.conf.wireguard" "/etc/resolv.conf"
    echo "Updated /etc/resolv.conf with NAME_SERVERS."
  fi
}

# Select VPN client
if [ "${VPN_CLIENT,,}" = "openvpn" ]; then
  start_openvpn
elif [ "${VPN_CLIENT,,}" = "wireguard" ]; then
  start_wireguard
elif [ "${VPN_CLIENT,,}" = "external" ] || [ "${VPN_CLIENT,,}" = "none" ]; then
  echo "[INFO] VPN_CLIENT is set to '${VPN_CLIENT}'. Skipping internal VPN setup."
  echo "[INFO] This mode is intended for use with an external VPN container (e.g., gluetun sidecar)."
  echo "[INFO] Ensure your network is already routed through a VPN before using this mode."

  # Set external mode marker
  echo "external" > "$VPN_INTERFACE_FILE"
  touch /tmp/vpn_external_mode

  # Wait for external VPN to be ready and record initial VPN IP
  echo "[INFO] Waiting for external VPN connection..."
  EXTERNAL_VPN_READY=false
  for i in $(seq 1 30); do
    CURRENT_IP=$(curl -sf --max-time 5 ifconfig.me 2>/dev/null || true)
    if [ -n "$CURRENT_IP" ]; then
      echo "[INFO] External IP detected: $CURRENT_IP"
      # Record this as our expected VPN IP for leak detection
      echo "$CURRENT_IP" > /tmp/expected_vpn_ip
      echo "$CURRENT_IP" > /tmp/last_external_ip
      EXTERNAL_VPN_READY=true
      break
    fi
    echo "[INFO] Waiting for network... ($i/30)"
    sleep 2
  done

  if [ "$EXTERNAL_VPN_READY" = "false" ]; then
    echo "[ERROR] Could not detect external IP. External VPN may not be ready."
    exit 1
  fi

  # Enable IP leak checking for external mode by default
  echo "[INFO] Enabling VPN monitoring for external mode..."
  echo "true" > /run/s6/container_environment/CHECK_IP_LEAK 2>/dev/null || true
  echo "true" > /run/s6/container_environment/CHECK_VPN_CONNECTIVITY 2>/dev/null || true
  echo "true" > /run/s6/container_environment/EXTERNAL_VPN_MODE 2>/dev/null || true

  # Export for current session
  export CHECK_IP_LEAK=true
  export CHECK_VPN_CONNECTIVITY=true
  export EXTERNAL_VPN_MODE=true

  touch /tmp/vpn_setup_complete
  echo "[INFO] External VPN mode configured."
  echo "[INFO] - VPN IP recorded: $(cat /tmp/expected_vpn_ip)"
  echo "[INFO] - IP leak detection: enabled"
  echo "[INFO] - NZBGet will be stopped if VPN connection is lost"
  echo "[INFO] --- End of vpn-setup.sh (external mode) ---"
  exit 0
else
  echo "[ERROR] Invalid VPN_CLIENT: $VPN_CLIENT. Must be 'openvpn', 'wireguard', 'external', or 'none'."
  exit 1
fi

# VPN interface setup will be handled by the s6 service
VPN_INTERFACE=$(cat "$VPN_INTERFACE_FILE")
echo "[INFO] VPN interface configuration: $VPN_INTERFACE"
echo "[INFO] Note: VPN connection will be established by the OpenVPN s6 service"

# --- IPTables and Routing ---
echo "[INFO] Configuring iptables and routing rules..."

# Get gateway for eth0 (Docker's bridge)
ETH0_GATEWAY=$(ip route | grep default | grep eth0 | awk '{print $3}')
if [ -z "$ETH0_GATEWAY" ]; then
    # Fallback for older ip route versions or different outputs
    ETH0_GATEWAY=$(ip route show dev eth0 | awk '/default via/ {print $3}')
fi
if [ -z "$ETH0_GATEWAY" ]; then
    # A common default if detection fails, but this is a guess
    ETH0_GATEWAY="172.17.0.1" # This often is the Docker host IP on the default bridge
    echo "[WARN] Could not reliably determine eth0 gateway. Using default $ETH0_GATEWAY. If UI is inaccessible, this might be the cause."
else
    echo "[INFO] Detected eth0 gateway: $ETH0_GATEWAY"
fi

# Get IP for eth0
ETH0_IP=$(ip -4 addr show dev eth0 | awk '/inet/ {print $2}' | cut -d/ -f1)
if [ -z "$ETH0_IP" ]; then
    echo "[WARN] Could not determine IP address of eth0. Policy routing for UI access might not be optimal."
else
    echo "[INFO] Detected eth0 IP: $ETH0_IP"
fi

# Flush existing rules (important for restarts or rule changes)
iptables -F INPUT
iptables -F FORWARD
iptables -F OUTPUT
iptables -t nat -F
iptables -t mangle -F
echo "[INFO] Flushed existing iptables rules."

# Set default policies - STRICT DENY-ALL APPROACH
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP # DROP by default for strict killswitch
echo "[INFO] Set strict default iptables policies (ALL chains set to DROP)."

# Allow loopback traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
echo "[INFO] Allowed loopback traffic."

# Allow established and related connections (standard rule)
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
# For FORWARD chain as well, if container were to act as a router for others (not typical for this use case but good practice)
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
echo "[INFO] Allowed established/related connections."

# DNS LEAK PREVENTION - Block DNS on eth0, only allow through VPN
echo "[INFO] Implementing DNS leak prevention..."
iptables -A OUTPUT -o eth0 -p udp --dport 53 -j DROP
iptables -A OUTPUT -o eth0 -p tcp --dport 53 -j DROP
iptables -A OUTPUT -o "$VPN_INTERFACE" -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -o "$VPN_INTERFACE" -p tcp --dport 53 -j ACCEPT
echo "[INFO] DNS leak prevention rules applied - DNS only allowed through VPN"

# Allow NZBGet UI access from host (Docker for Mac via 127.0.0.1 proxies to eth0 IP)
iptables -A INPUT -i eth0 -p tcp --dport 6789 -j ACCEPT
echo "[INFO] Added iptables rule to allow NZBGet UI on eth0:6789."

# Allow monitoring access from host
iptables -A INPUT -i eth0 -p tcp --dport 8080 -j ACCEPT
echo "[INFO] Added iptables rule to allow monitoring on eth0:8080."

# Policy routing for NZBGet UI, monitoring & Privoxy when accessed from host
# This ensures replies to connections hitting eth0 go back out via eth0 gateway, not VPN tunnel
echo "[INFO] Adding CONNMARK policy routing for UI access (mark 0x1, table 100)"

if [ -n "$ETH0_IP" ]; then
  echo "[INFO] Using specific eth0 IP $ETH0_IP for PREROUTING CONNMARK rules."
  # 1. On incoming connections to NZBGet on eth0, mark the connection
  iptables -t mangle -A PREROUTING -d "$ETH0_IP" -p tcp --dport 6789 -j CONNMARK --set-mark 0x1
else
  echo "[WARN] ETH0_IP not found. Using less specific -i eth0 for PREROUTING CONNMARK rule for NZBGet."
  iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport 6789 -j CONNMARK --set-mark 0x1
fi

# 2. Restore mark on packets belonging to these connections in OUTPUT chain
iptables -t mangle -A OUTPUT -p tcp --sport 6789 -j CONNMARK --restore-mark
# 3. Create a routing rule to use table 100 if mark is 0x1
ip rule add fwmark 0x1 lookup 100 priority 1000 2>/dev/null || true
# 4. Add a default route to table 100 via eth0 gateway
ip route add default via "$ETH0_GATEWAY" dev eth0 table 100 2>/dev/null || true

echo "[INFO] CONNMARK rules for NZBGet UI (port 6789) applied."

# Add CONNMARK rules for monitoring port 8080
if [ -n "$ETH0_IP" ]; then
  echo "[INFO] Adding CONNMARK rules for monitoring server on port 8080 to $ETH0_IP"
  iptables -t mangle -A PREROUTING -d "$ETH0_IP" -p tcp --dport 8080 -j CONNMARK --set-mark 0x1
else
  echo "[WARN] ETH0_IP not found, using less specific -i eth0 for PREROUTING CONNMARK rule for monitoring server."
  iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport 8080 -j CONNMARK --set-mark 0x1
fi
iptables -t mangle -A OUTPUT -p tcp --sport 8080 -j CONNMARK --restore-mark
echo "[INFO] CONNMARK rules for monitoring server (port 8080) applied."


# VPN is up, redirect all other OUTPUT traffic through VPN interface
# This is the main "kill switch" part.
# All OUTPUT not matching previous rules (like loopback, PBR for UI)
# and not going to LAN_NETWORK, will be forced via VPN.

# If LAN_NETWORK is set, allow traffic to it without VPN
if [ -n "$LAN_NETWORK" ]; then
  echo "[INFO] LAN_NETWORK ($LAN_NETWORK) is set. Adding route and iptables exception."
  # Add route for LAN_NETWORK to go via eth0's gateway
  ip route add "$LAN_NETWORK" via "$ETH0_GATEWAY" dev eth0
  # Allow output to LAN_NETWORK
  iptables -A OUTPUT -o eth0 -d "$LAN_NETWORK" -j ACCEPT
  # Allow input from LAN_NETWORK (e.g. for NZBGet calling back to a local Sonarr/Radarr)
  iptables -A INPUT -i eth0 -s "$LAN_NETWORK" -j ACCEPT
  echo "[INFO] Allowed traffic to/from LAN_NETWORK $LAN_NETWORK via eth0."
fi

# Allow specific additional ports if ADDITIONAL_PORTS is set
if [ -n "$ADDITIONAL_PORTS" ]; then
  OLD_IFS="$IFS"
  IFS=','
  for port_entry in $ADDITIONAL_PORTS; do
    IFS="$OLD_IFS" # Restore IFS for commands inside the loop
    port_num=$(echo "$port_entry" | cut -d'/' -f1 | xargs)
    proto=$(echo "$port_entry" | awk -F'/' '{if (NF>1) {print $2} else {print "tcp"}}' | xargs) # Default to tcp if no proto specified
    if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
        echo "[WARN] Invalid protocol '$proto' in ADDITIONAL_PORTS for entry '$port_entry'. Assuming tcp."
        proto="tcp"
    fi
    if [[ "$port_num" =~ ^[0-9]+$ ]] && [ "$port_num" -ge 1 ] && [ "$port_num" -le 65535 ]; then
      echo "[INFO] Allowing outbound traffic on $proto port $port_num via $VPN_INTERFACE."
      iptables -A OUTPUT -o "$VPN_INTERFACE" -p "$proto" --dport "$port_num" -j ACCEPT
    else
      echo "[WARN] Invalid port number '$port_num' in ADDITIONAL_PORTS for entry '$port_entry'. Skipping."
    fi
    IFS=',' # Re-set IFS for the loop
  done
  IFS="$OLD_IFS"
  echo "[INFO] Processed ADDITIONAL_PORTS."
fi

# All other OUTPUT traffic must go through VPN interface
iptables -A OUTPUT -o "$VPN_INTERFACE" -j ACCEPT

# CRITICAL FIX: Allow VPN server connectivity before applying kill switch
# This prevents the chicken-and-egg problem where the kill switch blocks
# the UDP traffic needed to establish the VPN connection
if [ "${VPN_CLIENT,,}" = "openvpn" ]; then
  echo "[INFO] Extracting VPN server details from OpenVPN config for kill switch exception..."
  TEMP_OVPN_CONFIG="/tmp/config.ovpn"
  
  if [ -f "$TEMP_OVPN_CONFIG" ]; then
    # Extract remote server and port from OpenVPN config
    VPN_SERVER_INFO=$(grep -E "^remote " "$TEMP_OVPN_CONFIG" | head -1)
    if [ -n "$VPN_SERVER_INFO" ]; then
      VPN_SERVER_HOST=$(echo "$VPN_SERVER_INFO" | awk '{print $2}')
      VPN_SERVER_PORT=$(echo "$VPN_SERVER_INFO" | awk '{print $3}')
      VPN_SERVER_PROTO=$(echo "$VPN_SERVER_INFO" | awk '{print $4}')
      
      # Default to UDP port 1194 if not specified
      [ -z "$VPN_SERVER_PORT" ] && VPN_SERVER_PORT="1194"
      [ -z "$VPN_SERVER_PROTO" ] && VPN_SERVER_PROTO="udp"
      
      echo "[INFO] VPN server: $VPN_SERVER_HOST:$VPN_SERVER_PORT ($VPN_SERVER_PROTO)"
      
      # Resolve hostname to IP if needed (DNS should work at this point)
      if echo "$VPN_SERVER_HOST" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        VPN_SERVER_IP="$VPN_SERVER_HOST"
      else
        echo "[INFO] Resolving VPN server hostname: $VPN_SERVER_HOST"
        # Filter out invalid IPv6 addresses like "::" and only get valid IPv4 addresses
        VPN_SERVER_IP=$(nslookup "$VPN_SERVER_HOST" | awk '/^Address: / { print $2 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        if [ -z "$VPN_SERVER_IP" ]; then
          # Fallback to getent hosts, also filtering for IPv4
          VPN_SERVER_IP=$(getent hosts "$VPN_SERVER_HOST" | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        fi
      fi
      
      if [ -n "$VPN_SERVER_IP" ]; then
        echo "[INFO] Adding kill switch exception for VPN server: $VPN_SERVER_IP:$VPN_SERVER_PORT ($VPN_SERVER_PROTO)"
        iptables -A OUTPUT -d "$VPN_SERVER_IP" -p "$VPN_SERVER_PROTO" --dport "$VPN_SERVER_PORT" -j ACCEPT
        echo "[INFO] VPN server connectivity exception added successfully"
      else
        echo "[WARN] Could not resolve VPN server IP for $VPN_SERVER_HOST. VPN connection may fail to establish."
      fi
    else
      echo "[WARN] No 'remote' directive found in OpenVPN config. Using fallback exception for common VPN ports."
      # Fallback: allow common OpenVPN ports
      iptables -A OUTPUT -p udp --dport 1194 -j ACCEPT
      iptables -A OUTPUT -p tcp --dport 1194 -j ACCEPT
    fi
  else
    echo "[WARN] OpenVPN config file not found at $TEMP_OVPN_CONFIG. Adding fallback VPN port exceptions."
    # Fallback: allow common OpenVPN ports
    iptables -A OUTPUT -p udp --dport 1194 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 1194 -j ACCEPT
  fi
elif [ "${VPN_CLIENT,,}" = "wireguard" ]; then
  echo "[INFO] WireGuard detected. Extracting endpoint from config for kill switch exception..."
  WG_CONFIG_FILE="$VPN_CONFIG"
  if [ -z "$WG_CONFIG_FILE" ]; then
    WG_CONFIG_FILE=$(find /config/wireguard -maxdepth 1 -name '*.conf' -print -quit)
  fi

  if [ -f "$WG_CONFIG_FILE" ]; then
    # Extract Endpoint from WireGuard config (format: Endpoint = hostname:port or ip:port)
    WG_ENDPOINT=$(grep -E "^Endpoint\s*=" "$WG_CONFIG_FILE" | head -1 | sed 's/.*=\s*//' | xargs)
    if [ -n "$WG_ENDPOINT" ]; then
      WG_SERVER_HOST=$(echo "$WG_ENDPOINT" | cut -d':' -f1)
      WG_SERVER_PORT=$(echo "$WG_ENDPOINT" | cut -d':' -f2)
      [ -z "$WG_SERVER_PORT" ] && WG_SERVER_PORT="51820"

      echo "[INFO] WireGuard endpoint: $WG_SERVER_HOST:$WG_SERVER_PORT"

      # Resolve hostname to IP if needed
      if echo "$WG_SERVER_HOST" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        WG_SERVER_IP="$WG_SERVER_HOST"
      else
        echo "[INFO] Resolving WireGuard server hostname: $WG_SERVER_HOST"
        WG_SERVER_IP=$(nslookup "$WG_SERVER_HOST" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        if [ -z "$WG_SERVER_IP" ]; then
          WG_SERVER_IP=$(getent hosts "$WG_SERVER_HOST" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        fi
      fi

      if [ -n "$WG_SERVER_IP" ]; then
        echo "[INFO] Adding kill switch exception for WireGuard server: $WG_SERVER_IP:$WG_SERVER_PORT (udp)"
        iptables -A OUTPUT -d "$WG_SERVER_IP" -p udp --dport "$WG_SERVER_PORT" -j ACCEPT
        echo "[INFO] WireGuard server connectivity exception added successfully"
      else
        echo "[WARN] Could not resolve WireGuard server IP for $WG_SERVER_HOST. Adding fallback exception."
        iptables -A OUTPUT -p udp --dport "$WG_SERVER_PORT" -j ACCEPT
      fi
    else
      echo "[WARN] No Endpoint found in WireGuard config. Adding fallback exception for port 51820."
      iptables -A OUTPUT -p udp --dport 51820 -j ACCEPT
    fi
  else
    echo "[WARN] WireGuard config file not found. Adding fallback port exception."
    iptables -A OUTPUT -p udp --dport 51820 -j ACCEPT
  fi
fi

# STRICT KILLSWITCH - Log and drop any remaining eth0 traffic
iptables -A OUTPUT -o eth0 -m limit --limit 1/min -j LOG --log-prefix "[KILLSWITCH-BLOCKED] " --log-level 4
iptables -A OUTPUT -o eth0 -j DROP # Drop if trying to go out eth0 and not LAN/PBR
echo "[INFO] Strict killswitch active: All non-VPN traffic on eth0 will be dropped."

# Privoxy: Apply firewall and PBR rules if enabled (s6 will start the service)
if [ "${ENABLE_PRIVOXY,,}" = "yes" ] || [ "${ENABLE_PRIVOXY,,}" = "true" ]; then
  echo "[INFO] Privoxy is enabled. Ensuring firewall and PBR rules for port ${PRIVOXY_PORT:-8118}."
  iptables -A INPUT -i eth0 -p tcp --dport "${PRIVOXY_PORT:-8118}" -j ACCEPT # Allow incoming to Privoxy

  if [ -n "$ETH0_IP" ]; then
    echo "[INFO] Adding CONNMARK rules for Privoxy on port ${PRIVOXY_PORT:-8118} to $ETH0_IP"
    iptables -t mangle -A PREROUTING -d "$ETH0_IP" -p tcp --dport "${PRIVOXY_PORT:-8118}" -j CONNMARK --set-mark 0x1
  else
    echo "[WARN] ETH0_IP not found, using less specific -i eth0 for PREROUTING CONNMARK rule for Privoxy."
    iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport "${PRIVOXY_PORT:-8118}" -j CONNMARK --set-mark 0x1
  fi
  iptables -t mangle -A OUTPUT -p tcp --sport "${PRIVOXY_PORT:-8118}" -j CONNMARK --restore-mark # For replies
  echo "[INFO] CONNMARK rules for Privoxy (port ${PRIVOXY_PORT:-8118}) applied."
else
  echo "[INFO] Privoxy is disabled."
fi

# Execute enhanced killswitch script for additional protection
if [ -f /root/vpn-killswitch.sh ]; then
    echo "[INFO] Executing enhanced VPN killswitch script..."
    /root/vpn-killswitch.sh || echo "[WARN] Killswitch script had warnings but continuing"
fi

# Create a flag file indicating VPN script completed successfully
# This is mostly for the healthcheck or external monitoring.
touch /tmp/vpn_setup_complete
echo "[INFO] VPN setup script finished. Container should now be routing traffic through VPN (if connection was successful)."
echo "[INFO] Final VPN interface: $(cat $VPN_INTERFACE_FILE)"
echo "[INFO] NZBGet UI should be accessible on host port 6789."
if [ "${ENABLE_PRIVOXY,,}" = "yes" ] || [ "${ENABLE_PRIVOXY,,}" = "true" ]; then
  echo "[INFO] Privoxy should be accessible on host port ${PRIVOXY_PORT:-8118}."
fi
date
echo "[INFO] --- End of vpn-setup.sh ---"

exit 0