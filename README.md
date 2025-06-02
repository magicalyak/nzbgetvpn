# 🛡️ NZBGet VPN Docker 🚀

[![Docker Pulls](https://img.shields.io/docker/pulls/magicalyak/nzbgetvpn)](https://hub.docker.com/r/magicalyak/nzbgetvpn) [![Docker Stars](https://img.shields.io/docker/stars/magicalyak/nzbgetvpn)](https://hub.docker.com/r/magicalyak/nzbgetvpn) [![Build Status](https://github.com/magicalyak/nzbgetvpn/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/magicalyak/nzbgetvpn/actions/workflows/build-and-publish.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Secure NZBGet downloads with automatic VPN protection.** This Docker container combines NZBGet with OpenVPN/WireGuard, ensuring all your downloads are protected by your VPN connection.

🔗 **Get it now:** `docker pull magicalyak/nzbgetvpn:latest`

## ✨ Key Features

- 🔒 **Automatic VPN Protection** - All NZBGet traffic routed through your VPN
- 🌐 **VPN Protocol Support** - Both OpenVPN and WireGuard
- 🏗️ **Multi-Platform** - Works on x86, ARM64 (Raspberry Pi, Apple Silicon)
- ⚙️ **Auto-Configuration** - Set up your news server via environment variables
- 📊 **Built-in Monitoring** - Health checks and metrics endpoints
- 🔄 **Self-Healing** - Automatic restart on VPN/service failures

## 🚀 Quick Start

### 1. Prepare Your System

Create directories for your data:

```bash
# Create data directories
mkdir -p ~/nzbgetvpn/{config/openvpn,downloads}

# Example directory structure:
# ~/nzbgetvpn/
# ├── config/
# │   └── openvpn/          # Put your .ovpn file here
# └── downloads/            # Downloads will go here
```

### 2. Get Your VPN Configuration

Download your VPN configuration file from your provider and place it in `~/nzbgetvpn/config/openvpn/`:

**Popular VPN providers:**
- [NordVPN OpenVPN configs](https://nordvpn.com/servers/)
- [ExpressVPN configs](https://www.expressvpn.com/setup#manual)
- [Surfshark configs](https://support.surfshark.com/hc/en-us/articles/360011051133)
- Most providers offer OpenVPN config downloads

### 3. Run the Container

**Basic OpenVPN example:**

```bash
docker run -d \
  --name nzbgetvpn \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 6789:6789 \
  -v ~/nzbgetvpn/config:/config \
  -v ~/nzbgetvpn/downloads:/downloads \
  -e VPN_CLIENT=openvpn \
  -e VPN_CONFIG=/config/openvpn/your-provider.ovpn \
  -e VPN_USER=your_vpn_username \
  -e VPN_PASS=your_vpn_password \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=America/New_York \
  magicalyak/nzbgetvpn:latest
```

**Replace these values:**
- `your-provider.ovpn` → your actual OpenVPN config filename
- `your_vpn_username` → your VPN username
- `your_vpn_password` → your VPN password
- `America/New_York` → your timezone

### 4. Access NZBGet

1. **Open your browser:** http://localhost:6789
2. **Default login:** Username: `nzbget`, Password: `tegbzn6789`
3. **⚠️ Important:** Change the password immediately in Settings → Security

### 5. Configure Your News Server

In NZBGet web interface:
1. Go to **Settings → News-servers**
2. Configure **Server1** with your Usenet provider details
3. Test the connection and save

## 💡 Using Environment File (Recommended)

For easier management, create an `.env` file:

```bash
# Create .env file
cat > ~/nzbgetvpn/.env << 'EOF'
# VPN Settings
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/your-provider.ovpn
VPN_USER=your_vpn_username
VPN_PASS=your_vpn_password

# System Settings
PUID=1000
PGID=1000
TZ=America/New_York

# Optional: Auto-configure news server
NZBGET_S1_NAME=MyNewsServer
NZBGET_S1_HOST=news.provider.com
NZBGET_S1_PORT=563
NZBGET_S1_USER=news_username
NZBGET_S1_PASS=news_password
NZBGET_S1_CONN=15
NZBGET_S1_SSL=yes
EOF

# Run with environment file
docker run -d \
  --name nzbgetvpn \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 6789:6789 \
  -v ~/nzbgetvpn/config:/config \
  -v ~/nzbgetvpn/downloads:/downloads \
  --env-file ~/nzbgetvpn/.env \
  magicalyak/nzbgetvpn:latest
```

## 🐳 Docker Compose

Create `docker-compose.yml`:

```yaml
version: "3.8"

services:
  nzbgetvpn:
    image: magicalyak/nzbgetvpn:latest
    container_name: nzbgetvpn
    env_file: .env
    ports:
      - "6789:6789"        # NZBGet Web UI
      - "8080:8080"        # Monitoring (optional)
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    devices:
      - /dev/net/tun
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    restart: unless-stopped
```

Run with: `docker-compose up -d`

## 🔧 Essential Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `VPN_CLIENT` | VPN type (`openvpn` or `wireguard`) | `openvpn` |
| `VPN_CONFIG` | Path to config file inside container | `/config/openvpn/provider.ovpn` |
| `VPN_USER` | VPN username (OpenVPN) | `your_username` |
| `VPN_PASS` | VPN password (OpenVPN) | `your_password` |
| `PUID` | User ID for file permissions | `1000` |
| `PGID` | Group ID for file permissions | `1000` |
| `TZ` | Timezone | `America/New_York` |

## ✅ Verify Everything Works

```bash
# Check container is running
docker ps | grep nzbgetvpn

# Verify VPN connection (should show VPN IP, not your real IP)
docker exec nzbgetvpn curl -s ifconfig.me

# Check logs
docker logs nzbgetvpn --tail 20

# Access monitoring (if enabled)
curl http://localhost:8080/health
```

---

# 📚 Advanced Configuration

## 🌐 WireGuard Setup

WireGuard often provides better performance than OpenVPN:

```bash
# 1. Get WireGuard config from your provider
# 2. Place it in ~/nzbgetvpn/config/wireguard/

# 3. Update your .env file:
VPN_CLIENT=wireguard
VPN_CONFIG=/config/wireguard/wg0.conf

# 4. Add sysctls to docker run:
docker run -d \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  # ... other options
```

## 🔗 VPN Provider Examples

<details>
<summary><strong>🇺🇸 NordVPN</strong></summary>

**OpenVPN:**
```ini
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/us9999.nordvpn.com.ovpn
VPN_USER=your_nordvpn_username
VPN_PASS=your_nordvpn_password
```

**WireGuard:**
```ini
VPN_CLIENT=wireguard
VPN_CONFIG=/config/wireguard/nordvpn-us.conf
```

Download configs: [NordVPN Server List](https://nordvpn.com/servers/)

</details>

<details>
<summary><strong>🦈 Surfshark</strong></summary>

```ini
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/us-nyc.prod.surfshark.com_udp.ovpn
VPN_USER=your_surfshark_username
VPN_PASS=your_surfshark_password
```

Download configs: [Surfshark Manual Setup](https://support.surfshark.com/hc/en-us/articles/360011051133)

</details>

<details>
<summary><strong>🇸🇪 Mullvad (WireGuard Recommended)</strong></summary>

```ini
VPN_CLIENT=wireguard
VPN_CONFIG=/config/wireguard/mullvad-us.conf
```

Generate configs: [Mullvad Config Generator](https://mullvad.net/en/account/#/wireguard-config/)

</details>

<details>
<summary><strong>🛡️ Private Internet Access (PIA)</strong></summary>

```ini
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/us_east.ovpn
VPN_USER=your_pia_username
VPN_PASS=your_pia_password
```

</details>

<details>
<summary><strong>🔒 Privado VPN</strong></summary>

**OpenVPN:**
```ini
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/privado-us.ovpn
VPN_USER=your_privado_username
VPN_PASS=your_privado_password
```

**WireGuard:**
```ini
VPN_CLIENT=wireguard
VPN_CONFIG=/config/wireguard/privado-us.conf
```

Download configs: [Privado VPN Manual Setup](https://privadovpn.com/support/manual-setup/)

</details>

## 📊 Enhanced Monitoring & Auto-Restart

Enable advanced monitoring and automatic service recovery:

```ini
# In your .env file
ENABLE_MONITORING=yes
MONITORING_PORT=8080
ENABLE_AUTO_RESTART=true
RESTART_COOLDOWN_SECONDS=300
NOTIFICATION_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK
```

**Monitoring endpoints:**
- `http://localhost:8080/` - Dashboard
- `http://localhost:8080/health` - Health status
- `http://localhost:8080/metrics` - Metrics
- `http://localhost:8080/prometheus` - Prometheus metrics

**👉 Full guide:** [MONITORING.md](MONITORING.md)

## 🏗️ Multi-Architecture Support

nzbgetvpn supports multiple architectures natively:

| Platform | Architecture | Performance |
|----------|-------------|-------------|
| **Intel/AMD PCs** | linux/amd64 | Excellent |
| **Raspberry Pi 4/5** | linux/arm64 | Very Good |
| **Apple Silicon** | linux/arm64 | Excellent |
| **AWS Graviton** | linux/arm64 | Very Good |

**Platform-specific examples:**

<details>
<summary><strong>🍓 Raspberry Pi</strong></summary>

```bash
# ARM64-optimized settings
docker run -d \
  --name nzbgetvpn \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --device=/dev/net/tun \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  -p 6789:6789 \
  -e VPN_CLIENT=wireguard \
  -e NZBGET_S1_CONN=8 \
  -v ~/nzbgetvpn/config:/config \
  -v ~/nzbgetvpn/downloads:/downloads \
  magicalyak/nzbgetvpn:latest
```

</details>

**👉 Full guide:** [MULTI-ARCH.md](MULTI-ARCH.md)

## ⚙️ Advanced Environment Variables

<details>
<summary><strong>All Configuration Options</strong></summary>

**VPN Settings:**
- `VPN_CLIENT` - `openvpn` or `wireguard`
- `VPN_CONFIG` - Path to config file
- `VPN_USER` / `VPN_PASS` - OpenVPN credentials
- `VPN_OPTIONS` - Additional VPN client options
- `NAME_SERVERS` - Custom DNS servers

**System Settings:**
- `PUID` / `PGID` - User/Group IDs
- `TZ` - Timezone
- `UMASK` - File creation mask
- `LAN_NETWORK` - Local network CIDR
- `DEBUG` - Enable debug logging

**NZBGet Auto-Configuration:**
- `NZBGET_S1_NAME` - Server name
- `NZBGET_S1_HOST` - Server hostname
- `NZBGET_S1_PORT` - Server port
- `NZBGET_S1_USER` - Server username
- `NZBGET_S1_PASS` - Server password
- `NZBGET_S1_CONN` - Connection count
- `NZBGET_S1_SSL` - Enable SSL (`yes`/`no`)

**Monitoring & Auto-Restart:**
- `ENABLE_MONITORING` - Enable HTTP monitoring
- `MONITORING_PORT` - Monitoring server port
- `ENABLE_AUTO_RESTART` - Auto-restart failed services
- `RESTART_COOLDOWN_SECONDS` - Restart delay
- `NOTIFICATION_WEBHOOK_URL` - Discord/Slack webhooks

**Privoxy (Optional):**
- `ENABLE_PRIVOXY` - Enable HTTP proxy
- `PRIVOXY_PORT` - Proxy port

See [.env.sample](.env.sample) for complete list with examples.

</details>

## 🔧 Building from Source

```bash
# Clone repository
git clone https://github.com/magicalyak/nzbgetvpn.git
cd nzbgetvpn

# Build for current platform
docker build -t my-nzbgetvpn .

# Multi-architecture build
./scripts/build-multiarch.sh --platforms linux/amd64,linux/arm64
```

**👉 Build guide:** [scripts/README.md](scripts/README.md)

## 🔍 Troubleshooting

**Container won't start:**
- Check `docker logs nzbgetvpn`
- Verify VPN config file exists
- Ensure required capabilities are added

**VPN not connecting:**
- Enable debug: `DEBUG=true`
- Try different server/protocol
- Check VPN credentials

**Downloads not working:**
- Verify news server configuration
- Check NZBGet logs in web interface
- Test news server connectivity

**Permission errors:**
- Verify PUID/PGID match your user
- Check directory ownership

**👉 Full troubleshooting guide:** [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## 🤝 Contributing & Support

- 🐛 **Bug Reports:** [Bug Report template](https://github.com/magicalyak/nzbgetvpn/issues/new?template=bug_report.yml)
- 🚀 **Feature Requests:** [Feature Request template](https://github.com/magicalyak/nzbgetvpn/issues/new?template=feature_request.yml)
- ❓ **Questions:** [Question template](https://github.com/magicalyak/nzbgetvpn/issues/new?template=question.yml)

## 🙏 Acknowledgements

Thanks to:
- **LinuxServer.io** - Base NZBGet image
- **OpenVPN & WireGuard** - VPN implementations
- **Docker Community** - Multi-architecture tooling
- **jshridha/docker-nzbgetvpn** - Original inspiration

## 📜 License

MIT License - see [LICENSE](LICENSE) file for details.

---

**🚀 Ready to get started? Run the Quick Start commands above and have secure downloads in minutes!**