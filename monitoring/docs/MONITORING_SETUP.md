# nzbgetvpn Monitoring Setup Guide

This guide explains how to set up monitoring for your nzbgetvpn container using either Prometheus or InfluxDB2.

## Available Metrics

Your nzbgetvpn container exposes the following monitoring endpoints on port 8080:

- `/health` - Current health status (JSON)
- `/metrics` - Historical metrics and summary (JSON)
- `/status` - Detailed system status (JSON)
- `/logs` - Recent log entries (JSON)
- `/prometheus` - Prometheus-compatible metrics (text)

## Metrics Collected

- **Health Status**: Overall container health (healthy/unhealthy/degraded/warning)
- **Individual Checks**: NZBGet connectivity, VPN status, DNS resolution, IP leak detection
- **Response Times**: Average and maximum response times for each check type
- **Success Rates**: Percentage of successful checks for each check type
- **System Information**: Memory usage, load average, uptime
- **Network Information**: External IP address, VPN interface status

## Option 1: Prometheus + Grafana Setup

### Prerequisites
- Docker and Docker Compose installed
- Your nzbgetvpn container already running or configured

### Setup Steps

1. **Navigate to the monitoring directory and use the Prometheus docker-compose file**:
   ```bash
   cd monitoring/docker-compose
   
   # Start the monitoring stack
   docker-compose -f docker-compose.monitoring-prometheus.yml up -d
   ```

2. **Access the services**:
   - **Grafana**: http://localhost:3000 (admin/admin123)
   - **Prometheus**: http://localhost:9090
   - **nzbgetvpn monitoring**: http://localhost:8080

3. **View the dashboard**:
   - Login to Grafana
   - Navigate to Dashboards → nzbgetvpn Monitoring
   - The dashboard will show health status, response times, success rates, and individual check statuses

### Prometheus Configuration

The Prometheus configuration (`monitoring/prometheus.yml`) includes:

- **nzbgetvpn job**: Scrapes `/prometheus` endpoint every 30 seconds
- **nzbgetvpn-health job**: Monitors `/health` endpoint every 15 seconds
- **prometheus job**: Self-monitoring

### Available Prometheus Metrics

```
# Overall health status (1=healthy, 0=unhealthy)
nzbgetvpn_health_check

# Individual check status by check name
nzbgetvpn_check{check="nzbget|vpn|dns|ip_leak"}

# Response times for each check type
nzbgetvpn_response_time_seconds{check="type",stat="average|maximum"}

# Success rate percentage by check type
nzbgetvpn_success_rate_percent{check="type"}
```

## Option 2: InfluxDB2 + Telegraf + Grafana Setup

### Prerequisites
- Docker and Docker Compose installed
- Your nzbgetvpn container already running or configured

### Setup Steps

1. **Navigate to the monitoring directory and use the InfluxDB docker-compose file**:
   ```bash
   cd monitoring/docker-compose
   
   # Start the monitoring stack
   docker-compose -f docker-compose.monitoring-influxdb.yml up -d
   ```

2. **Access the services**:
   - **Grafana**: http://localhost:3000 (admin/admin123)
   - **InfluxDB**: http://localhost:8086 (admin/password123)
   - **nzbgetvpn monitoring**: http://localhost:8080

3. **Configure InfluxDB** (optional - already pre-configured):
   - Organization: `nzbgetvpn`
   - Bucket: `metrics`
   - Token: `nzbgetvpn-monitoring-token`

### Telegraf Configuration

The Telegraf configuration (`monitoring/telegraf.conf`) collects data from multiple endpoints:

- **JSON Metrics**: `/metrics` endpoint for detailed statistics
- **Health Status**: `/health` endpoint for current health
- **System Status**: `/status` endpoint for system information
- **Prometheus Metrics**: `/prometheus` endpoint as an alternative source

### InfluxDB Measurements

Data is stored in these InfluxDB measurements:

- `nzbgetvpn_summary` - Success rates, response times by check type
- `nzbgetvpn_health_status` - Overall health status and messages
- `nzbgetvpn_system` - System metrics (memory, load, uptime)
- Prometheus metrics (if using the prometheus input)

## Directory Structure

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
│   │   ├── dashboard.yml
│   │   └── nzbgetvpn-dashboard.json
│   └── datasources/
│       └── prometheus.yml
├── grafana-influx/                          # InfluxDB Grafana configs
│   ├── dashboards/
│   │   └── dashboard.yml
│   └── datasources/
│       └── influxdb.yml
├── prometheus.yml                           # Prometheus configuration
└── telegraf.conf                           # Telegraf configuration
```

## Customization

### Environment Variables

You can customize the monitoring behavior with these environment variables in your `.env` file:

```bash
# Monitoring server port (default: 8080)
MONITORING_PORT=8080

# Monitoring log level (default: INFO)
MONITORING_LOG_LEVEL=DEBUG

# Enable monitoring server (default: enabled if port is exposed)
ENABLE_MONITORING=yes
```

### Custom Alerts

#### Prometheus Alerting Rules

Create `monitoring/alert_rules.yml`:

```yaml
groups:
  - name: nzbgetvpn
    rules:
      - alert: NZBGetVPNDown
        expr: nzbgetvpn_health_check == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "nzbgetvpn container is unhealthy"
          description: "nzbgetvpn has been unhealthy for more than 2 minutes"

      - alert: VPNDisconnected
        expr: nzbgetvpn_check{check="vpn"} == 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "VPN connection lost"
          description: "VPN check is failing"

      - alert: HighResponseTime
        expr: nzbgetvpn_response_time_seconds{stat="average"} > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High response times detected"
          description: "Average response time is {{ $value }}s"
```

#### InfluxDB Alerting

Use InfluxDB's built-in alerting or integrate with external tools like Grafana alerts.

### Custom Dashboards

#### Prometheus/Grafana Queries

Useful PromQL queries for creating custom dashboards:

```promql
# Health status over time
nzbgetvpn_health_check

# Response time by check type
avg by (check) (nzbgetvpn_response_time_seconds{stat="average"})

# Success rate trend
avg_over_time(nzbgetvpn_success_rate_percent[1h])

# Check status matrix
nzbgetvpn_check
```

#### InfluxDB/Flux Queries

Useful Flux queries for InfluxDB dashboards:

```flux
// Health status over time
from(bucket: "metrics")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "nzbgetvpn_health_status")
  |> filter(fn: (r) => r._field == "overall_status")

// Average response times
from(bucket: "metrics")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "nzbgetvpn_summary")
  |> filter(fn: (r) => r._field == "avg_response_time")
  |> group(columns: ["check_type"])

// Memory usage trend
from(bucket: "metrics")
  |> range(start: -6h)
  |> filter(fn: (r) => r._measurement == "nzbgetvpn_system")
  |> filter(fn: (r) => r._field == "memory_usage_percent")
```

## Troubleshooting

### Common Issues

1. **Metrics not appearing**:
   - Check that port 8080 is exposed on your nzbgetvpn container
   - Verify the monitoring server is running: `curl http://localhost:8080/health`
   - Check container logs for monitoring-related errors

2. **Prometheus can't scrape metrics**:
   - Ensure containers are on the same Docker network
   - Check Prometheus targets page: http://localhost:9090/targets
   - Verify the `/prometheus` endpoint returns data

3. **InfluxDB connection issues**:
   - Check Telegraf logs: `docker logs telegraf`
   - Verify InfluxDB is accessible: `curl http://localhost:8086/health`
   - Confirm the token and organization settings

4. **Grafana dashboard shows no data**:
   - Check the data source connection in Grafana settings
   - Verify the time range matches when metrics started collecting
   - Use Grafana's query builder to test queries

5. **Docker-compose path issues**:
   - Ensure you're running docker-compose from the `monitoring/docker-compose/` directory
   - Check that your `.env` file is in the project root (two levels up from docker-compose files)
   - Verify config and downloads directories exist in the project root

### Log Files

Monitor these log files for troubleshooting:

- `/config/monitoring.log` - Monitoring server logs
- `/config/healthcheck.log` - Health check logs
- `/config/metrics.json` - Historical metrics data
- `/tmp/nzbgetvpn_status.json` - Current status file

### Manual Testing

Test the monitoring endpoints manually:

```bash
# Test health endpoint
curl http://localhost:8080/health | jq

# Test metrics endpoint
curl http://localhost:8080/metrics | jq

# Test Prometheus endpoint
curl http://localhost:8080/prometheus

# Test detailed status
curl http://localhost:8080/status | jq
```

## Security Considerations

1. **Change default passwords**: Update Grafana and InfluxDB passwords in the docker-compose files
2. **Network security**: Consider using Docker secrets for tokens and passwords
3. **Access control**: Implement reverse proxy with authentication for production use
4. **Token rotation**: Regularly rotate InfluxDB tokens and update configurations

## Performance Impact

The monitoring system is designed to be lightweight:

- **CPU usage**: Minimal, health checks run every 30 seconds
- **Memory usage**: ~50MB for metrics storage and monitoring server
- **Network usage**: ~1KB per metric collection interval
- **Storage**: Metrics are rotated automatically, ~10MB per day typical usage

## Integration with External Systems

### Alertmanager Integration

For Prometheus setups, integrate with Alertmanager for notifications:

```yaml
# Add to prometheus.yml
rule_files:
  - "alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
```

### Webhook Notifications

The monitoring endpoints can be integrated with external systems:

```bash
# Example webhook for health status changes
curl -X POST https://your-webhook-url.com/alert \
  -H "Content-Type: application/json" \
  -d "$(curl -s http://localhost:8080/health)"
```

This monitoring setup provides comprehensive visibility into your nzbgetvpn container's health and performance, helping you identify issues quickly and maintain optimal operation. 