# nzbgetvpn Monitoring

This directory contains comprehensive monitoring setups for the nzbgetvpn container using either Prometheus or InfluxDB2.

## Quick Start

Choose one of the monitoring stacks:

### Option 1: Prometheus + Grafana
```bash
cd docker-compose
docker-compose -f docker-compose.monitoring-prometheus.yml up -d
```

### Option 2: InfluxDB2 + Telegraf + Grafana
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