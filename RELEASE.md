# nzbgetvpn Release Notes

## v25.0.28 (2024-12-19)
**Fix: Monitoring Port Access**

### 🔧 Critical Fix
- **Added missing monitoring INPUT rule**: VPN setup script now includes `iptables -A INPUT -i eth0 -p tcp --dport 8080 -j ACCEPT`
- **External monitoring access**: Monitoring endpoint now accessible from outside container without manual intervention
- **Out-of-the-box functionality**: No more need for manual firewall rule additions after deployment

### 🛡️ Security & Reliability  
- **Maintains VPN security**: Only adds necessary rule for monitoring port 8080
- **Consistent with other ports**: Follows same pattern as NZBGet UI (6789) and Privoxy (8118) rules
- **Automatic application**: Rule applied during VPN setup, no user intervention required

### 🐛 Bug Fixes
- **Resolves monitoring access issues**: External health checks and dashboards now work immediately
- **Eliminates manual fixes**: No more need to manually add iptables INPUT rules
- **Consistent container behavior**: All exposed ports now properly accessible

### 📋 Technical Details
The monitoring port (8080) was missing an INPUT iptables rule, causing external access to be blocked even though the port was exposed. The VPN setup script already included INPUT rules for:
- Port 6789 (NZBGet UI) ✅
- Port 8118 (Privoxy) ✅
- Port 8080 (Monitoring) ❌ **[NOW FIXED]**

This release adds the missing rule to ensure consistency and immediate functionality.

---

## v25.0.28 (2024-12-19)
**Fix: Monitoring Port Access**

### 🔧 Critical Fix
- **Added missing monitoring INPUT rule**: VPN setup script now includes `iptables -A INPUT -i eth0 -p tcp --dport 8080 -j ACCEPT`
- **External monitoring access**: Monitoring endpoint now accessible from outside container without manual intervention
- **Out-of-the-box functionality**: No more need for manual firewall rule additions after deployment

### 🛡️ Security & Reliability  
- **Maintains VPN security**: Only adds necessary rule for monitoring port 8080
- **Consistent with other ports**: Follows same pattern as NZBGet UI (6789) and Privoxy (8118) rules
- **Automatic application**: Rule applied during VPN setup, no user intervention required

### 🐛 Bug Fixes
- **Resolves monitoring access issues**: External health checks and dashboards now work immediately
- **Eliminates manual fixes**: No more need to manually add iptables INPUT rules
- **Consistent container behavior**: All exposed ports now properly accessible

### 📋 Technical Details
The monitoring port (8080) was missing an INPUT iptables rule, causing external access to be blocked even though the port was exposed. The VPN setup script already included INPUT rules for:
- Port 6789 (NZBGet UI) ✅
- Port 8118 (Privoxy) ✅
- Port 8080 (Monitoring) ❌ **[NOW FIXED]**

This release adds the missing rule to ensure consistency and immediate functionality.

---

## v25.0.27 (2025-06-13)
**Fix: VPN Kill Switch Chicken-and-Egg Problem**

### 🔧 Critical Fix
- **Fixed VPN connection failure**: Resolved the chicken-and-egg problem where the VPN kill switch blocked the UDP traffic needed to establish the VPN connection
- **Smart kill switch logic**: Now extracts VPN server details from OpenVPN config and allows connectivity to VPN server before applying traffic blocking rules
- **Auto-detection**: Automatically detects and allows traffic to the specific VPN server IP and port from the config file
- **Multi-protocol support**: Handles both UDP and TCP VPN connections
- **WireGuard support**: Includes exception for standard WireGuard port (51820/udp)

### 🛡️ Security & Reliability
- **Maintains security**: Kill switch still blocks all non-VPN traffic, preventing IP leaks
- **Graceful fallbacks**: If server detection fails, adds exceptions for common VPN ports (1194)
- **DNS resolution**: Resolves VPN hostnames to IP addresses for precise firewall rules

### 🐛 Bug Fixes
- **Resolves monitoring "unhealthy" status**: VPN can now connect properly, allowing health monitoring to show correct status
- **Eliminates container startup failures**: No more VPN connection timeouts during container startup
- **Fixes transmission UDP blocking**: Resolves similar issues affecting other VPN-enabled containers

### 📋 Technical Details
The root cause was that the VPN kill switch (`iptables -A OUTPUT -o eth0 -j DROP`) was blocking ALL outbound traffic on eth0, including the UDP packets needed for OpenVPN to connect to the VPN server. This created a circular dependency:
1. Kill switch blocks UDP → VPN can't connect
2. VPN can't connect → tun0 interface never created  
3. No tun0 → traffic remains blocked by kill switch

The fix adds a specific exception rule (`iptables -A OUTPUT -d $VPN_SERVER_IP -p udp --dport $VPN_SERVER_PORT -j ACCEPT`) before the DROP rule.

### 🔄 Upgrade Path
- **Automatic**: Existing containers will get the fix on restart
- **No configuration changes required**
- **Maintains compatibility**: All existing VPN configs continue to work

---

## v25.0.26 (2025-06-13)

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