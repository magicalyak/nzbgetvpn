#!/command/with-contenv bash
# shellcheck shell=bash
# This script handles VPN provider auto-configuration
# When VPN_PROVIDER is set, it automatically downloads and configures VPN files

set -e

echo "[INFO] Starting VPN provider setup..."

# Skip if VPN_PROVIDER is not set or empty
if [ -z "$VPN_PROVIDER" ]; then
  echo "[INFO] VPN_PROVIDER not set, skipping provider auto-configuration."
  exit 0
fi

# Normalize provider name
PROVIDER="${VPN_PROVIDER,,}"
echo "[INFO] VPN provider detected: $PROVIDER"

# Ensure config directories exist
mkdir -p /config/openvpn /config/wireguard

case "$PROVIDER" in
  nordvpn)
    echo "[INFO] Setting up NordVPN..."

    # NordVPN requires service credentials
    if [ -z "$VPN_USER" ] || [ -z "$VPN_PASS" ]; then
      echo "[ERROR] NordVPN requires VPN_USER and VPN_PASS (service credentials from NordVPN dashboard)"
      exit 1
    fi

    # Determine server selection
    NORD_COUNTRY="${VPN_COUNTRY:-us}"
    NORD_SERVER="${VPN_SERVER:-}"

    if [ -n "$NORD_SERVER" ]; then
      # User specified a specific server
      CONFIG_URL="https://downloads.nordcdn.com/configs/files/ovpn_udp/servers/${NORD_SERVER}.nordvpn.com.udp.ovpn"
      CONFIG_FILE="/config/openvpn/${NORD_SERVER}.nordvpn.com.udp.ovpn"
    else
      # Use recommended server API
      echo "[INFO] Fetching recommended NordVPN server for country: $NORD_COUNTRY"

      # NordVPN API for recommended servers
      API_URL="https://api.nordvpn.com/v1/servers/recommendations?filters[country_id]=${NORD_COUNTRY}&limit=1"

      # Try to get recommended server
      RECOMMENDED=$(curl -sf "$API_URL" 2>/dev/null | jq -r '.[0].hostname // empty' || true)

      if [ -n "$RECOMMENDED" ]; then
        echo "[INFO] Recommended server: $RECOMMENDED"
        CONFIG_URL="https://downloads.nordcdn.com/configs/files/ovpn_udp/servers/${RECOMMENDED}.udp.ovpn"
        CONFIG_FILE="/config/openvpn/${RECOMMENDED}.udp.ovpn"
      else
        # Fallback to a known good US server
        echo "[WARN] Could not fetch recommended server, using fallback"
        CONFIG_URL="https://downloads.nordcdn.com/configs/files/ovpn_udp/servers/us9591.nordvpn.com.udp.ovpn"
        CONFIG_FILE="/config/openvpn/us9591.nordvpn.com.udp.ovpn"
      fi
    fi

    # Download config if not already present
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "[INFO] Downloading NordVPN config from: $CONFIG_URL"
      if curl -sf "$CONFIG_URL" -o "$CONFIG_FILE"; then
        echo "[INFO] Config downloaded successfully"
      else
        echo "[ERROR] Failed to download NordVPN config"
        exit 1
      fi
    else
      echo "[INFO] Using existing config: $CONFIG_FILE"
    fi

    # Set up credentials file
    echo "[INFO] Setting up NordVPN credentials"
    echo "$VPN_USER" > /config/openvpn/credentials.txt
    echo "$VPN_PASS" >> /config/openvpn/credentials.txt
    chmod 600 /config/openvpn/credentials.txt

    # Set VPN_CLIENT and VPN_CONFIG for vpn-setup.sh
    export VPN_CLIENT="openvpn"
    export VPN_CONFIG="$CONFIG_FILE"

    # Write to s6 environment (use printf to avoid trailing newline)
    printf "%s" "openvpn" > /run/s6/container_environment/VPN_CLIENT
    printf "%s" "$CONFIG_FILE" > /run/s6/container_environment/VPN_CONFIG

    echo "[INFO] NordVPN setup complete"
    ;;

  mullvad)
    echo "[INFO] Setting up Mullvad..."

    if [ -z "$VPN_USER" ]; then
      echo "[ERROR] Mullvad requires VPN_USER (your account number)"
      exit 1
    fi

    # Mullvad config URL pattern
    MULLVAD_COUNTRY="${VPN_COUNTRY:-us}"
    MULLVAD_CITY="${VPN_CITY:-}"

    if [ -n "$MULLVAD_CITY" ]; then
      CONFIG_NAME="mullvad_${MULLVAD_COUNTRY}_${MULLVAD_CITY}"
    else
      CONFIG_NAME="mullvad_${MULLVAD_COUNTRY}"
    fi

    CONFIG_FILE="/config/openvpn/${CONFIG_NAME}.ovpn"

    # Mullvad provides configs via their website - user needs to download manually
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "[WARN] Mullvad config not found at $CONFIG_FILE"
      echo "[INFO] Please download your Mullvad config from https://mullvad.net/en/account/#/openvpn-config"
      echo "[INFO] Place it in /config/openvpn/ and restart the container"
      exit 1
    fi

    # Set up credentials (Mullvad uses account number as username, 'm' as password)
    echo "$VPN_USER" > /config/openvpn/credentials.txt
    echo "m" >> /config/openvpn/credentials.txt
    chmod 600 /config/openvpn/credentials.txt

    export VPN_CLIENT="openvpn"
    export VPN_CONFIG="$CONFIG_FILE"
    printf "%s" "openvpn" > /run/s6/container_environment/VPN_CLIENT
    printf "%s" "$CONFIG_FILE" > /run/s6/container_environment/VPN_CONFIG

    echo "[INFO] Mullvad setup complete"
    ;;

  pia|privateinternetaccess)
    echo "[INFO] Setting up Private Internet Access..."

    if [ -z "$VPN_USER" ] || [ -z "$VPN_PASS" ]; then
      echo "[ERROR] PIA requires VPN_USER and VPN_PASS"
      exit 1
    fi

    PIA_REGION="${VPN_REGION:-us_california}"
    CONFIG_URL="https://www.privateinternetaccess.com/openvpn/openvpn-strong.zip"

    # PIA provides a zip of all configs - need to extract
    if [ ! -d "/config/openvpn/pia" ]; then
      echo "[INFO] Downloading PIA configs..."
      mkdir -p /tmp/pia
      if curl -sf "$CONFIG_URL" -o /tmp/pia/configs.zip; then
        unzip -q /tmp/pia/configs.zip -d /config/openvpn/pia/
        rm -rf /tmp/pia
        echo "[INFO] PIA configs downloaded"
      else
        echo "[ERROR] Failed to download PIA configs"
        exit 1
      fi
    fi

    # Find config for region
    CONFIG_FILE=$(find /config/openvpn/pia -name "*${PIA_REGION}*.ovpn" -print -quit)
    if [ -z "$CONFIG_FILE" ]; then
      echo "[WARN] Config for region $PIA_REGION not found, using US California"
      CONFIG_FILE=$(find /config/openvpn/pia -name "*US California*" -print -quit)
    fi

    if [ -z "$CONFIG_FILE" ]; then
      echo "[ERROR] Could not find any PIA config file"
      exit 1
    fi

    echo "$VPN_USER" > /config/openvpn/credentials.txt
    echo "$VPN_PASS" >> /config/openvpn/credentials.txt
    chmod 600 /config/openvpn/credentials.txt

    export VPN_CLIENT="openvpn"
    export VPN_CONFIG="$CONFIG_FILE"
    printf "%s" "openvpn" > /run/s6/container_environment/VPN_CLIENT
    printf "%s" "$CONFIG_FILE" > /run/s6/container_environment/VPN_CONFIG

    echo "[INFO] PIA setup complete"
    ;;

  surfshark)
    echo "[INFO] Setting up Surfshark..."

    if [ -z "$VPN_USER" ] || [ -z "$VPN_PASS" ]; then
      echo "[ERROR] Surfshark requires VPN_USER and VPN_PASS (service credentials)"
      exit 1
    fi

    SURFSHARK_SERVER="${VPN_SERVER:-us-nyc}"
    CONFIG_URL="https://my.surfshark.com/vpn/api/v1/server/configurations"
    CONFIG_FILE="/config/openvpn/${SURFSHARK_SERVER}.prod.surfshark.com_udp.ovpn"

    if [ ! -f "$CONFIG_FILE" ]; then
      echo "[INFO] Downloading Surfshark config..."
      DIRECT_URL="https://my.surfshark.com/vpn/api/v4/config/download/${SURFSHARK_SERVER}.prod.surfshark.com/udp"
      if curl -sf "$DIRECT_URL" -o "$CONFIG_FILE"; then
        echo "[INFO] Config downloaded"
      else
        echo "[WARN] Could not download config. Please manually download from Surfshark"
        exit 1
      fi
    fi

    echo "$VPN_USER" > /config/openvpn/credentials.txt
    echo "$VPN_PASS" >> /config/openvpn/credentials.txt
    chmod 600 /config/openvpn/credentials.txt

    export VPN_CLIENT="openvpn"
    export VPN_CONFIG="$CONFIG_FILE"
    printf "%s" "openvpn" > /run/s6/container_environment/VPN_CLIENT
    printf "%s" "$CONFIG_FILE" > /run/s6/container_environment/VPN_CONFIG

    echo "[INFO] Surfshark setup complete"
    ;;

  custom|manual)
    echo "[INFO] Custom/manual VPN provider - skipping auto-configuration"
    echo "[INFO] Please ensure your VPN config is in /config/openvpn or /config/wireguard"
    ;;

  *)
    echo "[WARN] Unknown VPN_PROVIDER: $PROVIDER"
    echo "[INFO] Supported providers: nordvpn, mullvad, pia, surfshark, custom"
    echo "[INFO] Falling back to manual configuration"
    ;;
esac

echo "[INFO] VPN provider setup complete"
exit 0
