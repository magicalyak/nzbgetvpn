# 📊 Enhanced Monitoring & Auto-Restart Guide

nzbgetvpn includes advanced monitoring and automatic restart capabilities to ensure maximum reliability and provide detailed insights into container health.

## 🚀 Quick Start

**Enable monitoring in your `.env` file:**
```ini
ENABLE_MONITORING=yes
MONITORING_PORT=8080
```

**Map the monitoring port in Docker:**
```bash
# Docker run
-p 8080:8080

# Docker Compose
ports:
  - "8080:8080"
```

**Access monitoring endpoints:**
- **Health Check:** `http://localhost:8080/health`
- **Metrics:** `http://localhost:8080/metrics`
- **Full Status:** `http://localhost:8080/status`
- **Logs:** `http://localhost:8080/logs`
- **Prometheus:** `http://localhost:8080/prometheus`

## 📋 Monitoring Features

### 🔍 Enhanced Health Checks

The health check system performs comprehensive monitoring:

- **NZBGet Responsiveness:** Verifies WebUI accessibility and response time
- **VPN Interface Status:** Checks if VPN tunnel is up and active
- **DNS Resolution:** Validates DNS functionality
- **IP Leak Detection:** Monitors for VPN IP leaks (optional)
- **News Server Connectivity:** Tests connection to configured news servers

### 📊 Metrics Collection

Detailed metrics are collected and stored:

- **Response Times:** For all health checks
- **Success Rates:** Historical success/failure ratios
- **Interface Statistics:** Network traffic on VPN interfaces
- **System Resources:** Memory usage and load averages
- **Connection Quality:** VPN stability metrics

### 🎯 Status Levels

Health checks return different status levels:

- **`healthy`** - All systems operational
- **`warning`** - Minor issues detected (e.g., news server unreachable)
- **`degraded`** - DNS or other non-critical issues
- **`unhealthy`** - Critical failures (VPN down, NZBGet not responding)

## 🌐 Monitoring Endpoints

### `/health` - Health Status
```bash
curl http://localhost:8080/health
```

**Response:**
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
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

**HTTP Status Codes:**
- `200` - Healthy or Warning
- `503` - Unhealthy or Degraded

### `/metrics` - Historical Metrics
```bash
curl http://localhost:8080/metrics
```

**Response:**
```json
{
  "summary": {
    "nzbget": {
      "success_rate": 99.8,
      "total_checks": 500,
      "avg_response_time": 0.045,
      "max_response_time": 0.120,
      "last_status": "success"
    },
    "vpn_interface": {
      "success_rate": 100.0,
      "total_checks": 500,
      "avg_response_time": 0.002,
      "max_response_time": 0.008,
      "last_status": "up"
    }
  },
  "metrics": [
    {
      "timestamp": "2024-01-15 10:30:00",
      "check": "nzbget",
      "status": "success",
      "response_time": 0.045,
      "details": ""
    }
  ]
}
```

### `/status` - Detailed System Status
```bash
curl http://localhost:8080/status
```

**Response:**
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "uptime": {
    "seconds": 86400,
    "human": "1 day, 0:00:00"
  },
  "system": {
    "memory": {
      "total": 8589934592,
      "available": 4294967296,
      "used": 4294967296,
      "usage_percent": 50.0
    },
    "load_average": {
      "1min": 0.15,
      "5min": 0.10,
      "15min": 0.05
    }
  },
  "vpn": {
    "tun0": {
      "exists": true,
      "up": true,
      "details": "inet 10.8.0.2/24..."
    }
  },
  "nzbget": {
    "responsive": true,
    "port": 6789
  },
  "network": {
    "external_ip": "203.0.113.42"
  }
}
```

### `/logs` - Recent Log Entries
```bash
# Get last 50 lines
curl http://localhost:8080/logs

# Get last 100 error logs
curl http://localhost:8080/logs?lines=100&level=ERROR
```

### `/prometheus` - Prometheus Metrics
```bash
curl http://localhost:8080/prometheus
```

**Response:**
```
# HELP nzbgetvpn_health_check Health check status (1=healthy, 0=unhealthy)
# TYPE nzbgetvpn_health_check gauge
nzbgetvpn_health_check 1
nzbgetvpn_check{check="nzbget"} 1
nzbgetvpn_check{check="vpn_interface"} 1

# HELP nzbgetvpn_response_time_seconds Response time for health checks
# TYPE nzbgetvpn_response_time_seconds gauge
nzbgetvpn_response_time_seconds{check="nzbget",stat="average"} 0.045
nzbgetvpn_response_time_seconds{check="nzbget",stat="maximum"} 0.120
nzbgetvpn_success_rate_percent{check="nzbget"} 99.8
```

## 📈 Monitoring with Prometheus & Grafana

This repository includes a pre-configured monitoring stack using [Prometheus](https://prometheus.io/) and [Grafana](https://grafana.com/) to visualize the metrics exposed by the `/prometheus` endpoint.

### Quick Start

1.  **Navigate to the `monitoring` directory:**
    ```bash
    cd monitoring
    ```

2.  **Customize `docker-compose.yml` (Optional):**
    Open `docker-compose.yml` and add your `nzbgetvpn` environment variables (e.g., for VPN configuration).

3.  **Launch the stack:**
    ```bash
    docker-compose up -d
    ```

4.  **Access Grafana:**
    Open your web browser and go to `http://localhost:3000`.
    - **Username:** `admin`
    - **Password:** `grafana`

The Prometheus data source and the nzbgetvpn dashboard will be automatically provisioned.

### Included Components

- **`docker-compose.yml`:** Orchestrates the `nzbgetvpn`, `prometheus`, and `grafana` services.
- **`prometheus.yml`:** Configures Prometheus to scrape metrics from `nzbgetvpn`.
- **`grafana-datasource.yml`:** Provisions the Prometheus datasource in Grafana.
- **`grafana-dashboard.json`:** The pre-built Grafana dashboard for visualizing metrics.

## 🔄 Auto-Restart System

### ⚙️ Configuration

Enable auto-restart in your `.env` file:

```ini
# Enable automatic restart functionality
ENABLE_AUTO_RESTART=true

# Restart settings
RESTART_COOLDOWN_SECONDS=300    # 5 minutes between restart attempts
MAX_RESTART_ATTEMPTS=3          # Maximum restart attempts before giving up
RESTART_ON_VPN_FAILURE=true     # Auto-restart VPN on failure
RESTART_ON_NZBGET_FAILURE=true  # Auto-restart NZBGet on failure
```

### 🔧 How It Works

1. **Continuous Monitoring:** Runs alongside health checks
2. **Failure Detection:** Identifies VPN disconnections or NZBGet crashes
3. **Cooldown Period:** Prevents rapid restart loops
4. **Intelligent Restart:** Uses appropriate restart methods for each service
5. **Verification:** Confirms successful restart before continuing
6. **Counter Reset:** Resets attempt counters after sustained health

### 📊 Restart Logic

**VPN Restart Process:**
1. Gracefully terminate existing VPN processes
2. Clean up network interfaces
3. Re-run VPN setup script
4. Verify interface is up and functional
5. Test external IP connectivity

**NZBGet Restart Process:**
1. Gracefully shutdown NZBGet
2. Force kill if needed
3. Restart via s6-overlay service
4. Verify process is running
5. Test WebUI responsiveness

### 🚨 Failure Scenarios

**Auto-restart will trigger on:**
- VPN interface goes down
- VPN connection drops
- NZBGet process crashes
- NZBGet becomes unresponsive

**Auto-restart will NOT trigger on:**
- DNS resolution failures (non-critical)
- News server connectivity issues (provider issue)
- IP leak detection warnings (informational)

## 🔔 Notification System

### 📧 Webhook Notifications

Configure webhook notifications for important events:

```ini
# Discord webhook example
NOTIFICATION_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN

# Slack webhook example  
NOTIFICATION_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK

# Custom webhook
NOTIFICATION_WEBHOOK_URL=https://your-server.com/webhook
```

### 📋 Notification Events

Notifications are sent for:
- **VPN Failure:** When VPN connection is lost
- **VPN Restart Success:** When VPN is successfully restarted
- **VPN Restart Failed:** When VPN restart attempts fail
- **NZBGet Failure:** When NZBGet becomes unresponsive
- **NZBGet Restart Success:** When NZBGet is successfully restarted
- **NZBGet Restart Failed:** When NZBGet restart attempts fail

### 📨 Notification Format

```json
{
  "event": "vpn_failure",
  "message": "VPN interface is down, attempting restart",
  "timestamp": "2024-01-15T10:30:00Z",
  "container": "nzbgetvpn"
}
```

## 📈 Integration Examples

### 🎯 Prometheus + Grafana

**prometheus.yml:**
```yaml
scrape_configs:
  - job_name: 'nzbgetvpn'
    static_configs:
      - targets: ['nzbgetvpn:8080']
    metrics_path: '/prometheus'
    scrape_interval: 30s
```

**Grafana Dashboard:**
- Import the provided Grafana dashboard JSON
- Monitor success rates, response times, and system health
- Set up alerts for critical failures

### 🔍 External Monitoring

**Uptime Monitoring:**
```bash
# Health check endpoint for external monitoring
curl -f http://your-server:8080/health
```

**Load Balancer Health Check:**
```yaml
# nginx upstream health check
upstream nzbgetvpn {
    server nzbgetvpn:6789;
    # Use monitoring endpoint for health
    health_check uri=/health port=8080;
}
```

### 🐳 Docker Health Integration

The enhanced health check integrates with Docker's health system:

```bash
# Check Docker health status
docker inspect nzbgetvpn | jq '.[0].State.Health'

# View health check logs  
docker inspect nzbgetvpn | jq '.[0].State.Health.Log'
```

## 🛠️ Advanced Configuration

### 🎛️ IP Leak Detection

**Configure expected VPN network:**
```ini
# For OpenVPN networks
VPN_NETWORK=10.8.*.*

# For WireGuard networks  
VPN_NETWORK=10.2.*.*

# Disable IP leak detection
DISABLE_IP_LEAK_CHECK=true
```

### 📊 Monitoring Verbosity

**Adjust logging levels:**
```ini
# Minimal logging
MONITORING_LOG_LEVEL=WARNING

# Debug logging (troubleshooting)
MONITORING_LOG_LEVEL=DEBUG
DEBUG=true
```

### 🔧 Custom Restart Behavior

**Fine-tune restart behavior:**
```ini
# Longer cooldown for unstable networks
RESTART_COOLDOWN_SECONDS=600    # 10 minutes

# More aggressive restart attempts
MAX_RESTART_ATTEMPTS=5

# Only restart VPN, not NZBGet
RESTART_ON_NZBGET_FAILURE=false
```

## 📂 Log Files

Monitoring generates several log files in `/config`:

- **`healthcheck.log`** - Health check results and timing
- **`monitoring.log`** - Monitoring server activity  
- **`auto-restart.log`** - Auto-restart events and actions
- **`metrics.json`** - Historical metrics data

## 🔍 Troubleshooting

### Common Issues

**Monitoring server won't start:**
```bash
# Check if Python3 is available
docker exec nzbgetvpn python3 --version

# Check monitoring logs
docker exec nzbgetvpn tail -f /config/monitoring.log
```

**Health checks failing:**
```bash
# Run health check manually
docker exec nzbgetvpn /root/healthcheck.sh

# Check health check logs
docker exec nzbgetvpn tail -f /config/healthcheck.log
```

**Auto-restart not working:**
```bash
# Verify auto-restart is enabled
docker exec nzbgetvpn env | grep ENABLE_AUTO_RESTART

# Check auto-restart logs
docker exec nzbgetvpn tail -f /config/auto-restart.log
```

### Debug Commands

```bash
# View current status file
docker exec nzbgetvpn cat /tmp/nzbgetvpn_status.json

# Check VPN interface
docker exec nzbgetvpn ip addr show

# Test external connectivity
docker exec nzbgetvpn curl -s ifconfig.me

# View all monitoring endpoints
curl http://localhost:8080/
```

---

For more troubleshooting help, see the main [Troubleshooting Guide](TROUBLESHOOTING.md). 