# nzbgetvpn Monitoring Setup Guide

This guide explains how to set up comprehensive monitoring for your nzbgetvpn container using either Prometheus or InfluxDB2 with beautiful, functional Grafana dashboards.

## 🎯 Available Metrics & Endpoints

Your nzbgetvpn container exposes the following monitoring endpoints on port 8080:

- `/health` - Current health status (JSON)
- `/metrics` - Historical metrics and summary (JSON)  
- `/status` - Detailed system status (JSON)
- `/logs` - Recent log entries (JSON)
- `/prometheus` - Prometheus-compatible metrics (text)

## 📊 Comprehensive Metrics Collected

### Health & Status Metrics
- **Overall Health**: Container health status (healthy/unhealthy/degraded/warning)
- **Individual Checks**: NZBGet connectivity, VPN status, DNS resolution, IP leak detection
- **Response Times**: Average and maximum response times for each check type
- **Success Rates**: Percentage of successful checks for each check type

### System Metrics
- **Memory Usage**: Usage percentage and available memory
- **CPU Usage**: Current CPU utilization percentage  
- **Load Average**: System load (1, 5, 15 minute averages)
- **Container Uptime**: How long the container has been running

### Network & VPN Metrics
- **External IP Address**: Current external IP (should be VPN IP)
- **VPN Interface Status**: Status of tun0/wg0 interfaces
- **IP Leak Detection**: Monitoring for IP leaks outside VPN

### Application Metrics
- **NZBGet Status**: Connectivity and responsiveness to NZBGet
- **Download Statistics**: Available through NZBGet API integration

## 🔗 Option 0: Integration with Existing Prometheus & Grafana

If you already have Prometheus and Grafana running, you can easily add nzbgetvpn monitoring without deploying additional containers.

### Prerequisites
- Existing Prometheus server
- Existing Grafana instance
- Your nzbgetvpn container running with monitoring enabled

### Step 1: Configure Prometheus Scraping

Add the following job to your existing `prometheus.yml` configuration:

```yaml
scrape_configs:
  # Add to your existing scrape_configs section
  - job_name: 'nzbgetvpn'
    static_configs:
      - targets: ['<nzbgetvpn-host>:8080']  # Replace with your container's IP/hostname
    metrics_path: '/prometheus'
    scrape_interval: 30s
    scrape_timeout: 10s

  # Optional: Separate job for health endpoint (faster alerting)
  - job_name: 'nzbgetvpn-health'
    static_configs:
      - targets: ['<nzbgetvpn-host>:8080']
    metrics_path: '/health'
    scrape_interval: 15s
    scrape_timeout: 5s
```

**Finding your nzbgetvpn container IP:**
```bash
# If using Docker Compose
docker inspect <compose-project>_nzbgetvpn_1 | grep IPAddress

# If using standalone Docker
docker inspect nzbgetvpn | grep IPAddress

# Or use container name if on same Docker network
# targets: ['nzbgetvpn:8080']
```

### Step 2: Reload Prometheus Configuration

```bash
# Send SIGHUP to reload config (if Prometheus supports it)
docker kill -s HUP prometheus

# Or restart Prometheus container
docker restart prometheus

# Verify targets are discovered
# Visit http://your-prometheus:9090/targets
```

### Step 3: Import Grafana Dashboard

1. **Download the dashboard JSON:**
   ```bash
   # From this repository
   wget https://raw.githubusercontent.com/your-repo/nzbgetvpn/main/monitoring/grafana/dashboards/nzbgetvpn-dashboard.json
   
   # Or copy from your local setup
   cp monitoring/grafana/dashboards/nzbgetvpn-dashboard.json /tmp/
   ```

2. **Import into Grafana:**
   - Open your Grafana instance
   - Go to **Dashboards** → **Import**
   - Click **Upload JSON file** and select `nzbgetvpn-dashboard.json`
   - Configure the Prometheus datasource (select your existing one)
   - Click **Import**

3. **Verify the dashboard:**
   - Navigate to the imported "🛡️ nzbgetvpn Monitoring Dashboard"
   - Confirm metrics are displaying correctly
   - Adjust time range and refresh interval as needed

### Step 4: Configure Alerting (Optional)

Add these alerting rules to your existing Prometheus rules:

```yaml
# Add to your existing alerting rules file
groups:
  - name: nzbgetvpn_alerts
    rules:
      - alert: NZBGetVPNDown
        expr: nzbgetvpn_health_check == 0
        for: 2m
        labels:
          severity: critical
          service: nzbgetvpn
        annotations:
          summary: "nzbgetvpn container is unhealthy"
          description: "Container has been unhealthy for more than 2 minutes"

      - alert: VPNDisconnected
        expr: nzbgetvpn_check{check="vpn_interface"} == 0
        for: 1m
        labels:
          severity: warning
          service: nzbgetvpn
        annotations:
          summary: "VPN connection lost"
          description: "VPN interface check is failing"

      - alert: IPLeakDetected
        expr: nzbgetvpn_check{check="ip_leak"} == 0
        for: 30s
        labels:
          severity: critical
          service: nzbgetvpn
        annotations:
          summary: "IP leak detected!"
          description: "Traffic may be bypassing VPN - immediate attention required"
```

### Troubleshooting Integration

**Metrics not appearing:**
```bash
# Test direct access to metrics endpoint
curl http://<nzbgetvpn-host>:8080/prometheus

# Check Prometheus targets page
# Look for nzbgetvpn job status

# Verify network connectivity
docker exec prometheus wget -qO- http://<nzbgetvpn-host>:8080/health
```

**Dashboard shows "No data":**
- Verify Prometheus datasource is correctly configured in Grafana
- Check that the job name in Prometheus matches dashboard queries
- Confirm time range covers period when container was running

**Container not accessible:**
```bash
# If containers are on different networks, create a bridge
docker network create monitoring
docker network connect monitoring nzbgetvpn
docker network connect monitoring prometheus

# Or use host networking (less secure)
# Add to nzbgetvpn: network_mode: "host"
```

## 🚀 Option 1: Complete Prometheus + Grafana Stack

If you don't have existing monitoring infrastructure, use our complete stack:

### Prerequisites
- Docker and Docker Compose installed
- Your nzbgetvpn container already running or configured

### Quick Setup

1. **Navigate to the monitoring directory and start the stack**:
   ```bash
   cd monitoring/docker-compose
   
   # Start the monitoring stack
   docker-compose -f docker-compose.monitoring-prometheus.yml up -d
   ```

2. **Access the services**:
   - **🎨 Grafana Dashboard**: http://localhost:3000 (admin/admin123)
   - **📊 Prometheus**: http://localhost:9090  
   - **🔧 nzbgetvpn Monitoring API**: http://localhost:8080

3. **View the enhanced dashboard**:
   - Login to Grafana with admin/admin123
   - Navigate to Dashboards → 🛡️ nzbgetvpn Monitoring Dashboard
   - Enjoy beautiful visualizations with:
     - ✅ Real-time health status indicators
     - 📈 Historical trend analysis
     - 🎯 Individual check status monitoring
     - 💻 System resource usage graphs
     - 🌐 VPN status and external IP tracking

### Prometheus Configuration

The enhanced Prometheus configuration includes:

```yaml
scrape_configs:
  # Main metrics endpoint (30s interval)
  - job_name: 'nzbgetvpn'
    static_configs:
      - targets: ['nzbgetvpn:8080']
    metrics_path: '/prometheus'
    scrape_interval: 30s
    
  # Health endpoint (15s interval for faster alerting)
  - job_name: 'nzbgetvpn-health'
    static_configs:
      - targets: ['nzbgetvpn:8080']
    metrics_path: '/health'
    scrape_interval: 15s
```

### 📊 Enhanced Dashboard Features

Our beautiful Grafana dashboard includes:

#### Status Overview Section
- **🟢 Health Status Indicator**: Color-coded health status (Green=Healthy, Red=Unhealthy)
- **⏱️ Container Uptime**: Shows how long the container has been running
- **🌐 External IP Display**: Current VPN IP address
- **📋 Health Check Table**: Status of all individual checks

#### Historical Analysis Section  
- **📈 Health Status Over Time**: Historical view of container health
- **🔍 Individual Check Status**: Track specific check failures over time
- **⚡ Response Times**: Monitor performance of health checks
- **📊 Success Rates**: Success percentage for each check type

#### System Resources Section
- **💾 Memory Usage**: Real-time memory consumption
- **⚙️ CPU Usage**: Current CPU utilization
- **📊 Load Average**: System load monitoring

### Available Prometheus Metrics

```promql
# Health status (1=healthy, 0=unhealthy)
nzbgetvpn_health_check

# Individual check status by type
nzbgetvpn_check{check="nzbget|vpn_interface|dns|ip_leak"}

# Response times with statistics
nzbgetvpn_response_time_seconds{check="type",stat="average|maximum"}

# Success rates by check type  
nzbgetvpn_success_rate_percent{check="type"}

# System metrics
nzbgetvpn_memory_usage_percent
nzbgetvpn_cpu_usage_percent  
nzbgetvpn_load_average

# Container info
nzbgetvpn_start_time
nzbgetvpn_external_ip_info{ip="x.x.x.x"}
```

## 🗄️ Option 2: InfluxDB2 + Telegraf + Grafana Setup

### Prerequisites
- Docker and Docker Compose installed
- Your nzbgetvpn container already running or configured

### Setup Steps

1. **Start the InfluxDB monitoring stack**:
   ```bash
   cd monitoring/docker-compose
   
   # Start the complete InfluxDB stack
   docker-compose -f docker-compose.monitoring-influxdb.yml up -d
   ```

2. **Access the services**:
   - **🎨 Grafana Dashboard**: http://localhost:3000 (admin/admin123)
   - **🗄️ InfluxDB UI**: http://localhost:8086 (admin/password123)
   - **🔧 nzbgetvpn Monitoring**: http://localhost:8080

3. **Pre-configured InfluxDB settings**:
   - **Organization**: `nzbgetvpn`
   - **Bucket**: `metrics`  
   - **Token**: `nzbgetvpn-monitoring-token`

### Telegraf Data Collection

Telegraf collects data from multiple endpoints:

```toml
# JSON metrics from /metrics endpoint
[[inputs.http]]
  urls = ["http://nzbgetvpn:8080/metrics"]
  data_format = "json"
  interval = "30s"
  
# Health status from /health endpoint  
[[inputs.http]]
  urls = ["http://nzbgetvpn:8080/health"]
  data_format = "json"
  interval = "15s"
  
# System status from /status endpoint
[[inputs.http]]
  urls = ["http://nzbgetvpn:8080/status"]
  data_format = "json"
  interval = "60s"
```

### InfluxDB Data Structure

Data is organized into these measurements:

```
nzbgetvpn_health_status
├── status (healthy/unhealthy/degraded/warning)
├── message (status message)
└── timestamp

nzbgetvpn_summary  
├── success_rate (by check_type tag)
├── avg_response_time (by check_type tag)
├── max_response_time (by check_type tag)
└── check_count

nzbgetvpn_system
├── memory_usage_percent
├── cpu_usage_percent
├── load_average_1min
├── uptime_seconds
└── external_ip
```

## 🎨 Dashboard Customization

### Color Schemes & Theming
- **Dark Theme**: Professional dark background for 24/7 monitoring
- **Color-coded Status**: Green (healthy), Red (unhealthy), Orange (degraded), Yellow (warning)
- **Threshold-based Coloring**: Automatic color changes based on metric values

### Panel Descriptions
Every panel includes helpful descriptions explaining:
- What the metric measures
- What values are expected
- When to be concerned about the values

### Auto-refresh
- **30-second refresh**: Dashboards automatically update every 30 seconds
- **Real-time monitoring**: Near real-time visibility into container health

## 🔔 Alerting & Notifications

### Prometheus Alerting Rules

Create `monitoring/alert_rules.yml`:

```yaml
groups:
  - name: nzbgetvpn_alerts
    rules:
      - alert: NZBGetVPNDown
        expr: nzbgetvpn_health_check == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "nzbgetvpn container is unhealthy"
          description: "Container has been unhealthy for more than 2 minutes"

      - alert: VPNDisconnected  
        expr: nzbgetvpn_check{check="vpn_interface"} == 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "VPN connection lost"
          description: "VPN interface check is failing"
          
      - alert: HighResponseTime
        expr: nzbgetvpn_response_time_seconds{stat="average"} > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High response times detected"
          description: "Average response time is {{ $value }}s"
          
      - alert: IPLeakDetected
        expr: nzbgetvpn_check{check="ip_leak"} == 0  
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "IP leak detected!"
          description: "Traffic may be bypassing VPN"
```

### InfluxDB Alerting (Kapacitor)

For InfluxDB setups, you can use Kapacitor for alerting:

```javascript
stream
  |from()
    .measurement('nzbgetvpn_health_status')
    .where(lambda: "host" == 'nzbgetvpn')
  |alert()
    .crit(lambda: "status" != 'healthy')
    .message('nzbgetvpn container is unhealthy: {{ .Level }}')
    .slack()
```

## 📁 Directory Structure

The monitoring setup is organized as follows:

```
monitoring/
├── docker-compose/                          # Docker Compose files
│   ├── docker-compose.monitoring-prometheus.yml
│   └── docker-compose.monitoring-influxdb.yml
├── docs/                                    # Documentation  
│   └── MONITORING_SETUP.md
├── grafana/                                 # Prometheus Grafana configs
│   ├── dashboards/
│   │   ├── dashboard.yml                    # Dashboard provisioning
│   │   └── nzbgetvpn-dashboard.json        # Beautiful Prometheus dashboard
│   └── datasources/
│       └── prometheus.yml                   # Prometheus datasource config
├── grafana-influx/                          # InfluxDB Grafana configs  
│   ├── dashboards/
│   │   ├── dashboard.yml                    # Dashboard provisioning
│   │   └── nzbgetvpn-influxdb-dashboard.json # Beautiful InfluxDB dashboard
│   └── datasources/
│       └── influxdb.yml                     # InfluxDB datasource config
├── prometheus.yml                           # Prometheus configuration
└── telegraf.conf                           # Telegraf configuration
```

## ⚙️ Environment Variables & Customization

### Monitoring Configuration

Customize monitoring behavior in your `.env` file:

```bash
# Enable monitoring server (default: yes)
ENABLE_MONITORING=yes

# Monitoring server port (default: 8080)  
MONITORING_PORT=8080

# Monitoring log level (default: INFO)
MONITORING_LOG_LEVEL=INFO

# Debug mode for troubleshooting
DEBUG=false
```

### Dashboard Customization

#### Time Ranges
- **Default**: Last 1 hour
- **Available**: 5m, 15m, 30m, 1h, 3h, 6h, 12h, 24h, 2d, 7d, 30d

#### Refresh Intervals  
- **Default**: 30 seconds
- **Available**: 5s, 10s, 30s, 1m, 5m, 15m, 30m, 1h

## 🔧 Troubleshooting

### Common Issues

**Dashboard shows "No data":**
```bash
# Check if monitoring server is running
curl http://localhost:8080/health

# Check Prometheus targets
# Visit http://localhost:9090/targets

# Check container logs
docker logs nzbgetvpn
docker logs prometheus  
docker logs grafana
```

**High response times:**
```bash
# Enable debug logging
echo "DEBUG=true" >> .env
docker restart nzbgetvpn

# Check detailed status
curl http://localhost:8080/status | jq
```

**Missing metrics in InfluxDB:**
```bash
# Check Telegraf logs
docker logs telegraf

# Verify InfluxDB connection
curl http://localhost:8086/health

# Check bucket and token configuration
```

### Performance Optimization

For better performance with large datasets:

```bash
# Prometheus retention (in docker-compose)
--storage.tsdb.retention.time=30d

# InfluxDB retention policy
influx setup --retention 2160h  # 90 days

# Reduce scrape intervals for less critical metrics
scrape_interval: 60s  # Instead of 30s
```

## 🛡️ Security Considerations

### Production Deployment

1. **Change default passwords**: Update Grafana and InfluxDB passwords
2. **Network security**: Use Docker secrets for tokens and passwords
3. **Access control**: Configure authentication and authorization
4. **Token rotation**: Regularly rotate InfluxDB tokens
5. **HTTPS**: Enable TLS for web interfaces

### Secure Configuration Example

```yaml
# docker-compose.override.yml
version: "3.8"
services:
  grafana:
    environment:
      - GF_SECURITY_ADMIN_PASSWORD_FILE=/run/secrets/grafana_password
    secrets:
      - grafana_password
      
secrets:
  grafana_password:
    external: true
```

## 🎯 What Makes These Dashboards Special

### 🎨 Beautiful Design
- **Modern Dark Theme**: Easy on the eyes for 24/7 monitoring
- **Color-coded Status**: Instant visual feedback on system health
- **Professional Layout**: Clean, organized panels with logical grouping

### 📊 Comprehensive Coverage  
- **Health Monitoring**: Overall and individual check status
- **Performance Metrics**: Response times and success rates
- **System Resources**: Memory, CPU, and load monitoring
- **Network Status**: VPN IP and connectivity tracking

### 🚀 User Experience
- **Instant Updates**: 30-second auto-refresh for real-time monitoring
- **Helpful Descriptions**: Every panel explains what it shows
- **Quick Links**: Direct access to monitoring API and management interfaces
- **Mobile Friendly**: Responsive design works on all devices

### 🔍 Troubleshooting Ready
- **Historical Analysis**: Track issues over time
- **Detailed Drill-down**: Click through for more information
- **Log Integration**: Recent events and log entries
- **Alert Integration**: Ready for alerting configuration

---

**🎉 Ready to monitor like a pro?** Choose your stack (Prometheus or InfluxDB) and enjoy beautiful, comprehensive monitoring of your nzbgetvpn container! 