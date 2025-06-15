# nzbgetvpn Monitoring

This directory contains comprehensive monitoring setups for the nzbgetvpn container using either Prometheus or InfluxDB2.

## Quick Start

Choose one of the monitoring options:

### Option 0: Integration with Existing Prometheus & Grafana

If you already have Prometheus and Grafana running:

1. **Add to your Prometheus config:**
   ```yaml
   scrape_configs:
     - job_name: 'nzbgetvpn'
       static_configs:
         - targets: ['<nzbgetvpn-host>:8080']
       metrics_path: '/prometheus'
       scrape_interval: 30s
   ```

2. **Import the Grafana dashboard:**
   - Copy `grafana/dashboards/nzbgetvpn-dashboard.json`
   - Import via Grafana UI: Dashboards → Import → Upload JSON file

3. **Reload Prometheus:**
   ```bash
   docker restart prometheus  # or send SIGHUP
   ```

See [docs/MONITORING_SETUP.md](docs/MONITORING_SETUP.md#-option-0-integration-with-existing-prometheus--grafana) for detailed integration instructions.

### Option 1: Complete Prometheus + Grafana Stack
```bash
cd docker-compose
docker-compose -f docker-compose.monitoring-prometheus.yml up -d
```

### Option 2: Complete InfluxDB2 + Telegraf + Grafana Stack
```bash
cd docker-compose
docker-compose -f docker-compose.monitoring-influxdb.yml up -d
```

## Access Points

- **Grafana**: http://localhost:3000 (admin/admin123)
- **Prometheus**: http://localhost:9090 (if using Prometheus stack)
- **InfluxDB**: http://localhost:8086 (admin/password123, if using InfluxDB stack)
- **nzbgetvpn monitoring**: http://localhost:8080

## Directory Structure

- `docker-compose/` - Docker Compose files for both monitoring stacks
- `docs/` - Complete setup guide and troubleshooting
- `grafana/` - Grafana configuration for Prometheus setup
- `grafana-influx/` - Grafana configuration for InfluxDB setup
- `prometheus.yml` - Prometheus configuration
- `telegraf.conf` - Telegraf configuration for InfluxDB

## Documentation

See [docs/MONITORING_SETUP.md](docs/MONITORING_SETUP.md) for complete setup instructions, customization options, and troubleshooting guides.

## What's Monitored

- Container health status
- VPN connectivity
- NZBGet responsiveness
- DNS resolution
- IP leak detection
- System metrics (memory, load, uptime)
- Response times and success rates 