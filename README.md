# 🛡️ NZBGet VPN Docker 🚀

[![Docker Pulls](https://img.shields.io/docker/pulls/magicalyak/nzbgetvpn)](https://hub.docker.com/r/magicalyak/nzbgetvpn) [![Docker Stars](https://img.shields.io/docker/stars/magicalyak/nzbgetvpn)](https://hub.docker.com/r/magicalyak/nzbgetvpn) [![Build Status](https://github.com/magicalyak/nzbgetvpn/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/magicalyak/nzbgetvpn/actions/workflows/build-and-publish.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Secure NZBGet downloads with automatic VPN protection.** This Docker container combines NZBGet with OpenVPN/WireGuard, ensuring all your downloads are protected by your VPN connection.

🔗 **Get it now:** `docker pull magicalyak/nzbgetvpn:latest`

## ✨ Key Features

- 🔒 **Enhanced VPN Kill Switch** - Strict firewall rules with DNS leak prevention
- 🛡️ **Active VPN Monitoring** - Automatically stops NZBGet if VPN connection fails
- 🌐 **VPN Protocol Support** - Both OpenVPN and WireGuard
- 🏗️ **Multi-Platform** - Works on x86, ARM64 (Raspberry Pi, Apple Silicon)
- ⚙️ **Auto-Configuration** - Set up your news server via environment variables
- 📊 **Built-in Monitoring** - Health checks and Prometheus metrics endpoints
- 🔄 **Self-Healing** - Automatic restart on VPN/service failures
- 🐧 **BusyBox Compatible** - Works reliably across all Linux distributions

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

**🔐 VPN Credentials (OpenVPN only):**

You have two options for providing VPN credentials:

**Option 1: Environment Variables** (quick setup)
```bash
-e VPN_USER=your_vpn_username \
-e VPN_PASS=your_vpn_password \
```

**Option 2: Credentials File** (more secure, recommended)
```bash
# Create credentials file (more secure than environment variables)
echo "your_vpn_username" > ~/nzbgetvpn/config/openvpn/credentials.txt
echo "your_vpn_password" >> ~/nzbgetvpn/config/openvpn/credentials.txt

# Don't set VPN_USER/VPN_PASS when using file method
```

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
      # - "8118:8118"      # Privoxy (uncomment if ENABLE_PRIVOXY=yes)
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

## ☸️ Kubernetes/K3s Deployment

Deploy nzbgetvpn on Kubernetes or K3s with proper VPN isolation and monitoring.

**Quick K3s deployment:**

```bash
# Create namespace and secrets
kubectl create namespace nzbgetvpn
kubectl create secret generic vpn-config \
  --from-file=provider.ovpn=/path/to/vpn-config.ovpn \
  -n nzbgetvpn

# Deploy using kubectl
kubectl apply -f https://raw.githubusercontent.com/magicalyak/nzbgetvpn/main/k8s/deployment.yaml
```

**Features:**
- VPN-isolated pods with NET_ADMIN capabilities
- Persistent storage for config and downloads
- Health monitoring and auto-restart
- Prometheus metrics integration
- Ingress support for external access

**👉 Complete K3s/Kubernetes guide:** [K3S_DEPLOYMENT.md](K3S_DEPLOYMENT.md)

## 🔧 Essential Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `VPN_CLIENT` | VPN type (`openvpn` or `wireguard`) | `openvpn` |
| `VPN_PROVIDER` | Auto-configure for provider (see below) | `nordvpn` |
| `VPN_CONFIG` | Path to config file inside container | `/config/openvpn/provider.ovpn` |
| `VPN_USER` | VPN username (OpenVPN) | `your_username` |
| `VPN_PASS` | VPN password (OpenVPN) | `your_password` |
| `VPN_COUNTRY` | Country code for auto-config | `us` |
| `PUID` | User ID for file permissions | `1000` |
| `PGID` | Group ID for file permissions | `1000` |
| `TZ` | Timezone | `America/New_York` |

## 🚀 Auto-Configuration with VPN Providers

Set `VPN_PROVIDER` to automatically download and configure your VPN - no manual config files needed:

```bash
docker run -d \
  --name nzbgetvpn \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 6789:6789 \
  -v ~/nzbgetvpn/config:/config \
  -v ~/nzbgetvpn/downloads:/downloads \
  -e VPN_PROVIDER=nordvpn \
  -e VPN_USER=your_service_username \
  -e VPN_PASS=your_service_password \
  -e VPN_COUNTRY=us \
  -e PUID=1000 \
  -e PGID=1000 \
  magicalyak/nzbgetvpn:latest
```

### Supported Providers

| Provider | `VPN_PROVIDER` | Credentials Required |
|----------|----------------|---------------------|
| NordVPN | `nordvpn` | Service credentials (from account dashboard) |
| Mullvad | `mullvad` | Account number |
| PIA | `pia` | Username/password |
| Surfshark | `surfshark` | Service credentials |

### Provider-Specific Options

| Variable | Description | Example |
|----------|-------------|---------|
| `VPN_COUNTRY` | Country for server selection | `us`, `uk`, `de` |
| `VPN_SERVER` | Specific server hostname | `us9591` |
| `VPN_REGION` | Region (PIA) | `us_california` |

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

## 📊 Monitoring with Prometheus & Grafana

nzbgetvpn includes comprehensive monitoring capabilities with Prometheus metrics, health checks, and status endpoints.

### Quick Monitoring Setup

**1. Enable monitoring in your `.env` file:**
```bash
ENABLE_MONITORING=yes
MONITORING_PORT=8080
```

**2. Expose monitoring port in docker-compose.yml:**
```yaml
ports:
  - "6789:6789"    # NZBGet
  - "8080:8080"    # Monitoring
```

**3. Configure Prometheus to scrape metrics:**
```yaml
# Add to your prometheus.yml
scrape_configs:
  - job_name: 'nzbgetvpn-metrics'
    static_configs:
      - targets: ['your-host:8080']
    metrics_path: '/prometheus'
    scrape_interval: 30s
```

### Available Endpoints

| Endpoint | Description | Format |
|----------|-------------|--------|
| `/health` | Current health status | JSON |
| `/prometheus` | Prometheus metrics | Text |
| `/status` | Detailed system info | JSON |
| `/metrics` | Historical metrics | JSON |

### Example Health Response

```json
{
  "timestamp": "2025-01-19T15:30:00Z",
  "status": "healthy",
  "exit_code": 0,
  "vpn_interface": "tun0", 
  "external_ip": "203.0.113.42",
  "checks": {
    "nzbget": "success",
    "vpn_interface": "up",
    "dns": "success",
    "news_server": "success"
  }
}
```

> ✅ **Health monitoring now works correctly on all architectures!** Recent fixes resolved BusyBox compatibility issues and improved status reporting.

### Prometheus Metrics

The container provides these key metrics:

- `nzbgetvpn_health_check` - Overall health (1=healthy, 0=unhealthy)
- `nzbgetvpn_check{check="service"}` - Individual service status
- `nzbgetvpn_response_time_seconds` - Response times for health checks
- `nzbgetvpn_success_rate_percent` - Success rates by service

### Docker Compose with Monitoring Stack

```yaml
version: '3.8'
services:
  nzbgetvpn:
    image: magicalyak/nzbgetvpn:latest
    devices:
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    environment:
      - ENABLE_MONITORING=yes
      - VPN_CLIENT=openvpn
      - VPN_CONFIG=/config/openvpn/your-provider.ovpn
    ports:
      - "6789:6789"
      - "8080:8080"

  prometheus:
    image: prom/prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml

  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
```

**👉 Complete monitoring guide:** [monitoring/docs/MONITORING_SETUP.md](monitoring/docs/MONITORING_SETUP.md)

## 🔍 Enhanced Health Checks

nzbgetvpn includes **comprehensive health monitoring** similar to transmissionvpn with configurable security checks:

### **Core Application Monitoring**
- ✅ **NZBGet responsiveness** - Web interface + JSON-RPC API validation
- ✅ **VPN interface status** - Automated detection of tun0/wg0 interfaces  
- ✅ **VPN connectivity** - Active network testing through VPN tunnel
- ✅ **DNS resolution** - Prevents DNS failures and routing issues

### **Security & Leak Detection**
- 🔐 **IP leak detection** - Monitors external IP changes
- 🔐 **DNS leak detection** - Tracks DNS server changes
- 🔐 **News server connectivity** - Validates Usenet server access
- 🔐 **Network routing** - Ensures traffic flows through VPN

### **Health Check Configuration**

```yaml
environment:
  # Enable comprehensive monitoring
  - METRICS_ENABLED=true
  - DEBUG=true
  
  # Security-focused monitoring
  - CHECK_DNS_LEAK=true
  - CHECK_IP_LEAK=true
  - CHECK_VPN_CONNECTIVITY=true
  - CHECK_NEWS_SERVER=true
  
  # Customize check behavior
  - HEALTH_CHECK_HOST=cloudflare.com
  - HEALTH_CHECK_TIMEOUT=15
  - EXTERNAL_IP_SERVICE=icanhazip.com
```

### **Health Status Levels**
- **healthy** (green) - All checks passed
- **warning** (yellow) - Non-critical issues (news server, IP changes)
- **degraded** (orange) - Important issues (DNS, VPN connectivity)  
- **unhealthy** (red) - Critical issues (NZBGet down, VPN interface down)

### **Testing Health Checks**

```bash
# Run health check manually
docker exec nzbgetvpn /root/healthcheck.sh
echo "Exit code: $?"

# View detailed health status
docker exec nzbgetvpn cat /tmp/nzbgetvpn_status.json | jq '.'

# Monitor health logs in real-time
docker exec nzbgetvpn tail -f /config/healthcheck.log
```

**👉 Complete configuration guide:** [HEALTHCHECK_OPTIONS.md](HEALTHCHECK_OPTIONS.md)

## 🔧 Enhanced Monitoring & Auto-Restart

Enable advanced monitoring and automatic service recovery:

```ini
# In your .env file
ENABLE_MONITORING=yes
MONITORING_PORT=8080
ENABLE_AUTO_RESTART=true
RESTART_COOLDOWN_SECONDS=300
NOTIFICATION_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK
```

**Auto-restart features:**
- Automatically restarts VPN connection if it fails
- Monitors NZBGet health and restarts if needed
- Configurable cooldown periods to prevent restart loops
- Discord/Slack notifications for service events

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

**VPN Kill Switch & Security:**
- `VPN_CHECK_INTERVAL` - Seconds between VPN health checks (default: 30)
- `VPN_MAX_FAILURES` - Max consecutive failures before stopping NZBGet (default: 3)
- `CHECK_DNS` - Enable DNS resolution testing (default: false)
- `CHECK_EXTERNAL_IP` - Check external IP through VPN (default: false)
- `AUTO_RESTART_VPN` - Auto-restart VPN on failure (default: false)

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
- `ENABLE_PRIVOXY` - Enable HTTP proxy (`yes`/`no`, default `no`)
- `PRIVOXY_PORT` - Proxy port (default `8118`)

> **Note:** Privoxy is disabled by default. Enabling it is a two-step change: set `ENABLE_PRIVOXY=yes` **and** publish the port in `docker-compose.yml` (e.g. `- "8118:8118"`). Publishing the port alone does nothing — the s6-rc service exits at startup unless `ENABLE_PRIVOXY` is set. See [Optional: Privoxy HTTP Proxy](#-optional-privoxy-http-proxy) below for details.

See [.env.sample](.env.sample) for complete list with examples.

</details>

## 🌐 Optional: Privoxy HTTP Proxy

The image bundles [Privoxy](https://www.privoxy.org/) so you can route browser or client HTTP traffic through the same VPN tunnel as NZBGet. It is **disabled by default**. Enabling it requires two changes:

**1. Enable the service** in your `.env`:

```bash
ENABLE_PRIVOXY=yes
PRIVOXY_PORT=8118    # optional, defaults to 8118
```

**2. Publish the port** in `docker-compose.yml`:

```yaml
ports:
  - "6789:6789"      # NZBGet Web UI
  - "8118:8118"      # Privoxy (must match PRIVOXY_PORT)
```

That's it. On startup the container generates `/etc/privoxy/config` from a template, starts Privoxy under s6 supervision, and `vpn-setup.sh` adds the iptables rules so traffic to port 8118 enters via `eth0` and replies route back out the LAN interface (not the VPN). Configure your browser or HTTP client to use `http://<docker-host>:8118` as an HTTP proxy and outbound traffic will exit through your VPN provider.

**Notes:**
- If you set `PRIVOXY_PORT` to a non-default value (e.g. `8119`), publish the matching port mapping in compose.
- If publishing the port without `ENABLE_PRIVOXY=yes`, the s6-rc privoxy service exits at startup with a one-time log message and nothing listens on the port.
- Custom filter/action files can be dropped in `/config/privoxy/`; otherwise built-in defaults are used. Set `PRIVOXY_SKIP_FILE_SETUP=yes` to disable automatic file management.

## 🛠️ Building Fixed Version

If you encounter issues with the standard image, we provide a fixed version with BusyBox compatibility improvements:

```bash
# Build the fixed version
chmod +x build-fixed.sh
./build-fixed.sh

# Use the fixed image
docker-compose.yml:
  image: magicalyak/nzbgetvpn:fixed
```

The fixed version includes:
- ✅ **BusyBox grep compatibility** - Fixes health check issues on some systems
- ✅ **Enhanced monitoring** - Improved Prometheus metrics collection  
- ✅ **Better VPN integration** - Resolved device mapping issues

**When to use the fixed version:**
- Health checks show "unknown" status despite working VPN
- Monitoring endpoints return incomplete data
- Running on systems with BusyBox utilities (Alpine, some routers)

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

**Monitoring shows "unknown" status:**
- Try the fixed image: `magicalyak/nzbgetvpn:fixed`
- Check if `/dev/net/tun` device is mapped correctly
- Enable debug logging: `DEBUG=true`

**👉 Full troubleshooting guide:** [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## 🔒 Security Documentation

- **[VPN Kill Switch Security](docs/VPN_KILLSWITCH_SECURITY.md)** - Enhanced security features and kill switch implementation
- **[Docker Scout Improvements](docs/DOCKER_SCOUT_IMPROVEMENTS.md)** - Security hardening recommendations

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