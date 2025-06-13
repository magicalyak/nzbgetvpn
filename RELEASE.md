# Release Instructions - Fixed Version with Monitoring

This document outlines the process for creating and releasing the fixed version of nzbgetvpn with BusyBox compatibility and enhanced monitoring.

## What's Fixed in This Release

### ✅ BusyBox Compatibility
- **Fixed health check script** - Replaced `grep -oP` with BusyBox-compatible sed commands
- **IP address extraction** - Now works reliably across all Linux distributions
- **Monitoring status** - Individual service checks now report correctly

### ✅ Enhanced Monitoring
- **Prometheus metrics** - Full integration with /prometheus endpoint
- **Health endpoints** - Comprehensive status reporting
- **Auto-restart capabilities** - Service recovery and notifications
- **Docker device mapping** - Proper /dev/net/tun configuration

### ✅ Documentation Updates
- **Monitoring guide** - Complete MONITORING.md documentation
- **Docker Compose** - Updated with device mapping requirements
- **Troubleshooting** - BusyBox-specific solutions

## Build and Release Process

### 1. Prerequisites
```bash
# Ensure Docker buildx is available
docker buildx version

# Setup multi-architecture builder (if not exists)
docker buildx create --name multiarch --use
```

### 2. Build the Fixed Image
```bash
# Build for multiple architectures
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f Dockerfile.fixed \
  -t magicalyak/nzbgetvpn:fixed \
  -t magicalyak/nzbgetvpn:latest-fixed \
  --push .

# Build and test locally first
docker build -f Dockerfile.fixed -t nzbgetvpn:test-fixed .
```

### 3. Testing Checklist

**Local Testing:**
```bash
# Test basic functionality
docker run --rm \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -e VPN_CLIENT=openvpn \
  nzbgetvpn:test-fixed \
  grep -n "sed -n" /root/healthcheck.sh

# Test health check compatibility
docker run --rm nzbgetvpn:test-fixed /root/healthcheck.sh --version
```

**Integration Testing:**
- [ ] VPN connection works with device mapping
- [ ] Health check reports proper IP addresses
- [ ] Prometheus metrics endpoint responds correctly
- [ ] Individual service checks show proper status
- [ ] Multi-architecture builds work on ARM64
- [ ] BusyBox grep commands execute without errors

### 4. Release Tags

Create the following tags:
- `magicalyak/nzbgetvpn:fixed` - Main fixed version
- `magicalyak/nzbgetvpn:latest-fixed` - Alternative latest fixed
- `magicalyak/nzbgetvpn:v1.0.0-fixed` - Version-specific fixed

### 5. Documentation Updates

**Update these files:**
- [ ] README.md - Add monitoring section
- [ ] MONITORING.md - Complete monitoring guide
- [ ] docker-compose.yml - Include device mapping
- [ ] .env.sample - Add monitoring variables
- [ ] TROUBLESHOOTING.md - BusyBox solutions

### 6. GitHub Release

**Create release with:**
- Tag: `v1.0.0-fixed`
- Title: "Fixed Version - BusyBox Compatibility & Enhanced Monitoring"
- Assets: Include build-fixed.sh and example configs

**Release Notes Template:**
```markdown
## 🎉 nzbgetvpn Fixed Version - v1.0.0

This release addresses BusyBox compatibility issues and enhances monitoring capabilities.

### ✅ What's Fixed
- **BusyBox grep compatibility** - Health checks now work on all Linux distributions
- **VPN interface detection** - Proper IP address extraction across platforms
- **Monitoring improvements** - Complete Prometheus integration
- **Device mapping** - Docker Compose includes required /dev/net/tun mapping

### 🚀 New Features
- **Enhanced health endpoints** - /health, /prometheus, /status, /metrics
- **Auto-restart capabilities** - Service recovery with notifications
- **Multi-architecture support** - AMD64, ARM64 with optimizations
- **Comprehensive monitoring** - Grafana dashboards and alerting

### 🐳 Quick Start
```bash
# Use the fixed image
docker run -d \
  --name nzbgetvpn \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 6789:6789 \
  -p 8080:8080 \
  magicalyak/nzbgetvpn:fixed
```

### 📊 Monitoring
- Health: http://localhost:8080/health
- Metrics: http://localhost:8080/prometheus
- Dashboard: http://localhost:8080/

### 🔧 Migration from Standard Version
1. Update docker-compose.yml: `image: magicalyak/nzbgetvpn:fixed`
2. Add device mapping: `devices: - /dev/net/tun`
3. Enable monitoring: `ENABLE_MONITORING=yes`

See [MONITORING.md](MONITORING.md) for complete setup guide.
```

### 7. Post-Release Tasks

**Update Docker Hub:**
- [ ] Update repository description
- [ ] Add monitoring tags/keywords
- [ ] Update README on Docker Hub

**Community Updates:**
- [ ] Update Reddit posts about the fixes
- [ ] Notify users who reported BusyBox issues
- [ ] Update relevant GitHub issue threads

## Rollback Plan

If issues are discovered:

```bash
# Revert to previous version
docker pull magicalyak/nzbgetvpn:latest

# Update compose files
sed -i 's/:fixed/:latest/g' docker-compose.yml
```

## Version History

| Version | Changes | Date |
|---------|---------|------|
| v1.0.0-fixed | BusyBox compatibility, enhanced monitoring | 2025-06-13 |
| latest | Original version with monitoring | 2025-06-11 |

## Support

For issues with the fixed version:
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Review [MONITORING.md](MONITORING.md) 
3. Open issue with "fixed-version" label 