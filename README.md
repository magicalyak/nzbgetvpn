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
    metrics_path: '/metrics'
    scrape_interval: 30s
```

`/prometheus` serves the same exposition, so existing scrape configs keep working.

### Available Endpoints

| Endpoint | Description | Format |
|----------|-------------|--------|
| `/metrics` | Prometheus metrics | Text |
| `/prometheus` | Same as `/metrics` | Text |
| `/health` | Current health status (503 when unhealthy, degraded or stale) | JSON |
| `/status` | Detailed system info | JSON |
| `/metrics.json` | Historical check records (needs `METRICS_ENABLED=true`) | JSON |

The monitoring server runs the health check itself every `HEALTH_CHECK_INTERVAL` seconds (default 30) and scrapes read the cached result, so a scrape never waits on network probes. This also means health data exists under Kubernetes, which ignores the Dockerfile `HEALTHCHECK`.

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

| Metric | Meaning |
|--------|---------|
| `nzbgetvpn_healthy` | 1 when the latest health check is fresh and reported `healthy`. Alert on this. |
| `nzbgetvpn_vpn_connected` | 1 when traffic actually passes through the tunnel: an ICMP probe bound to the VPN interface (`VPN_PROBE_HOST`, falling back to `VPN_PROBE_HOST_FALLBACK`) got a reply. Omitted when `CHECK_VPN_CONNECTIVITY=false`. |
| `nzbgetvpn_vpn_interface_up` | 1 when the VPN interface is up and has an address. This does **not** mean traffic passes; a dead tunnel usually keeps its address. |
| `nzbgetvpn_check{check="..."}` | Result of each check in the latest run (1 pass, 0 fail). Checks that did not run are omitted. |
| `nzbgetvpn_response_time_seconds{check="..."}` | How long each check took in the latest run |
| `nzbgetvpn_success_rate_percent{check="..."}` | Share of the last `SUCCESS_RATE_WINDOW` runs (default 20) in which each check passed |
| `nzbgetvpn_health_check_timestamp_seconds` | When the latest health check finished |
| `nzbgetvpn_health_check` | Deprecated alias of `nzbgetvpn_healthy` |

System gauges (`nzbgetvpn_memory_usage_percent`, `nzbgetvpn_cpu_usage_percent`, `nzbgetvpn_load_average`, `nzbgetvpn_start_time`, `nzbgetvpn_external_ip_info`) are unchanged.

A result older than `HEALTH_STATUS_MAX_AGE` seconds (default 180) reports `nzbgetvpn_healthy` and `nzbgetvpn_vpn_connected` as 0, so a probe that stops running cannot keep reporting its last good result.

Example alert rules:

```yaml
- alert: NZBGetVPNUnhealthy
  expr: nzbgetvpn_healthy == 0
  for: 5m
- alert: NZBGetVPNTunnelDown
  expr: nzbgetvpn_vpn_connected == 0
  for: 5m
- alert: NZBGetNewsServerDown
  expr: nzbgetvpn_success_rate_percent{check="news_server"} < 50
  for: 10m
```

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

The Docker `HEALTHCHECK` runs `/root/healthcheck-cached.sh`, which reports the result the monitoring server cached in `/tmp/nzbgetvpn_status.json` and only runs the full check when that result is missing or older than `HEALTHCHECK_CACHE_MAX_AGE` seconds, so the probes are not run twice.

**👉 Complete configuration guide:** [HEALTHCHECK_OPTIONS.md](HEALTHCHECK_OPTIONS.md)

## 🔧 Enhanced Monitoring & Auto-Restart

Enable advanced monitoring and automatic service recovery:

```ini
# In your .env file
ENABLE_MONITORING=yes
MONITORING_PORT=8080
ENABLE_AUTO_RESTART=true
RESTART_COOLDOWN_SECONDS=300
MAX_RESTART_ATTEMPTS=3
EXIT_ON_MAX_RESTARTS=true
NOTIFICATION_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK
```

**Auto-restart features:**
- Restarts the VPN when the tunnel stops passing traffic, not only when the interface disappears
- Monitors NZBGet health and restarts it through s6 if needed
- Acts only after `RESTART_FAILURE_THRESHOLD` consecutive failed checks, so one dropped probe does not bounce the tunnel
- Ignores checks until VPN setup has finished and `AUTO_RESTART_STARTUP_GRACE` seconds (default 120) have passed, so a tunnel and NZBGet that are still starting are not counted as failures
- Cooldown between restarts to prevent restart loops
- Discord/Slack notifications for service events

**When restarts run out:** once a service has been restarted `MAX_RESTART_ATTEMPTS` times without recovering, the container exits with code 1 (`EXIT_ON_MAX_RESTARTS=true`, the default). Docker restart policies and Kubernetes then replace it. Without this the watchdog would stop trying while the web UI stayed up, and a TCP liveness probe on port 6789 would never notice. Set `EXIT_ON_MAX_RESTARTS=false` to keep the old behaviour of logging and waiting.

A restart counter resets only after `HEALTHY_CHECKS_BEFORE_RESET` consecutive passing checks (default 5), so a tunnel that comes back for a single check between failures still runs out of attempts. With the defaults, a tunnel that stays dead is restarted three times and the container exits about 17 minutes after the tunnel died.

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
- `HEALTH_CHECK_INTERVAL` - Seconds between health checks run by the monitoring server (default: 30)
- `HEALTH_STATUS_MAX_AGE` - Seconds after which a health result counts as stale and unhealthy (default: 180)
- `SUCCESS_RATE_WINDOW` - Runs used for `nzbgetvpn_success_rate_percent` (default: 20)
- `VPN_PROBE_HOST` / `VPN_PROBE_HOST_FALLBACK` - Targets pinged through the VPN interface to test the tunnel (default: `1.1.1.1` / `9.9.9.9`)
- `ENABLE_AUTO_RESTART` - Auto-restart failed services (default: false)
- `RESTART_COOLDOWN_SECONDS` - Minimum seconds between restarts of a service (default: 300)
- `MAX_RESTART_ATTEMPTS` - Restarts per service before giving up (default: 3)
- `EXIT_ON_MAX_RESTARTS` - Exit the container with code 1 once restarts are used up (default: true)
- `RESTART_FAILURE_THRESHOLD` - Consecutive failed checks before a restart (default: 3)
- `HEALTHY_CHECKS_BEFORE_RESET` - Consecutive passing checks before a restart counter resets (default: 5)
- `AUTO_RESTART_CHECK_INTERVAL` - Seconds between watchdog passes (default: 30)
- `AUTO_RESTART_STARTUP_GRACE` - Seconds after VPN setup finishes before failures count (default: 120)
- `AUTO_RESTART_SETUP_TIMEOUT` - Seconds to wait for VPN setup before counting failures anyway (default: 600)
- `HEALTHCHECK_CACHE_MAX_AGE` - Oldest cached health result the Docker `HEALTHCHECK` will report before running the full check itself (default: 90)
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

**Kill switch.** `vpn-setup.sh` keeps the default iptables and ip6tables policies at DROP the whole time, including while the tunnel comes up and when the watchdog reruns it. Until the kill switch is built, only loopback and the VPN servers are allowed out, plus DNS to the configured nameservers when a server is a hostname; OpenVPN hostnames are then pinned to the addresses they resolved to. After that, traffic is allowed only through the tunnel interface, to each VPN server endpoint (every `remote` in an OpenVPN config, every WireGuard `Endpoint`), on loopback, for the configured UI ports, `LAN_NETWORK` and `ADDITIONAL_PORTS`, and for established connections, which may leave `eth0` only as replies to inbound connections. DNS queries on `eth0` are dropped, so lookups only go through the tunnel. NZBGet, Privoxy and the monitoring services start only after `vpn-setup.sh` has finished. If the tunnel stops passing traffic, the auto-restart watchdog (`ENABLE_AUTO_RESTART=true`) restarts it and, after `MAX_RESTART_ATTEMPTS`, exits the container so Docker or Kubernetes replaces it. `./test-killswitch.sh <container>` checks the firewall rules against a running container.

- **[Docker Scout Improvements](docs/DOCKER_SCOUT_IMPROVEMENTS.md)** - Security hardening recommendations

## 🧪 Running the Tests

The fast tests run in CI on every pull request and before each release is published:

```bash
python3 test-metrics-render.py

docker build -t nzbgetvpn:test .
docker run --rm --entrypoint bash -v "$PWD:/src:ro" nzbgetvpn:test /src/test-auto-restart.sh
docker run --rm --entrypoint bash -v "$PWD:/src:ro" nzbgetvpn:test /src/test-healthcheck-cached.sh
```

`test-dead-tunnel.sh` is an end-to-end test against real containers and is run by hand. It needs no VPN account: it stands in a fake `tun0`, kills it with an iptables rule, and checks the metrics and that the watchdog exits the container. It takes about 10 minutes and needs a Docker host that allows `NET_ADMIN` and `/dev/net/tun`:

```bash
./test-dead-tunnel.sh nzbgetvpn:test
```

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