# 🔧 nzbgetvpn Troubleshooting Guide

This guide covers common issues and their solutions when running nzbgetvpn. For provider-specific configurations, see the [VPN Provider Examples](README.md#-vpn-provider-examples) section in the README.

## 📋 Quick Diagnostics

Before diving into specific issues, run these commands to gather information:

```bash
# Check container status
docker ps -a | grep nzbgetvpn

# View recent logs
docker logs nzbgetvpn --tail 50

# Check IP address (should show VPN IP, not your real IP)
docker exec nzbgetvpn curl -s ifconfig.me

# Check DNS resolution
docker exec nzbgetvpn nslookup google.com

# Check VPN interface
docker exec nzbgetvpn ip addr show
```

## 🔌 VPN Connection Issues

### Problem: Container starts but VPN doesn't connect

**Symptoms:**
- Container starts but exits after a few seconds
- Logs show OpenVPN/WireGuard connection failures
- IP check shows your real IP instead of VPN IP

**Solutions:**

1. **Check VPN configuration file:**
   ```bash
   # Verify your config file exists and is readable
   docker exec nzbgetvpn ls -la /config/openvpn/
   docker exec nzbgetvpn ls -la /config/wireguard/
   ```

2. **Verify credentials (OpenVPN):**
   ```bash
   # Check if credentials file exists (if using file method)
   docker exec nzbgetvpn cat /config/openvpn/credentials.txt
   
   # Or verify environment variables are set
   docker exec nzbgetvpn env | grep VPN_
   ```

3. **Enable debug logging:**
   ```ini
   # In your .env file
   DEBUG=true
   ```

4. **Try different server/protocol:**
   - Switch from UDP to TCP or vice versa
   - Try a different VPN server location
   - For problematic providers, try different config files

### Problem: VPN connects but frequently disconnects

**Solutions:**

1. **Add VPN stability options:**
   ```ini
   VPN_OPTIONS=--inactive 3600 --ping-restart 60 --persist-key --persist-tun
   ```

2. **Check MTU settings:**
   ```ini
   # Try smaller MTU if having connection issues
   VPN_OPTIONS=--mtu 1200
   ```

3. **Use TCP instead of UDP:**
   - Download TCP version of your provider's config
   - TCP is more stable but slightly slower

### Problem: Cannot resolve DNS names

**Symptoms:**
- VPN connects but downloads fail
- DNS resolution fails inside container

**Solutions:**

1. **Set custom DNS servers:**
   ```ini
   NAME_SERVERS=1.1.1.1,8.8.8.8
   ```

2. **Check VPN's DNS configuration:**
   ```bash
   docker exec nzbgetvpn cat /etc/resolv.conf
   ```

## 🐳 Docker Container Issues

### Problem: Permission denied errors

**Symptoms:**
- Cannot write to `/downloads` or `/config`
- NZBGet reports permission errors
- Files created with wrong ownership

**Solutions:**

1. **Check and fix PUID/PGID:**
   ```bash
   # Find your user ID
   id yourusername
   
   # Set in .env file
   PUID=1000
   PGID=1000
   ```

2. **Fix existing file permissions:**
   ```bash
   # On your host system
   sudo chown -R 1000:1000 /opt/nzbgetvpn_data/config
   sudo chown -R 1000:1000 /opt/nzbgetvpn_data/downloads
   ```

3. **Create directories with correct ownership before first run:**
   ```bash
   HOST_DATA_DIR="/opt/nzbgetvpn_data"
   mkdir -p "${HOST_DATA_DIR}"/{config,downloads}
   sudo chown -R $(id -u):$(id -g) "${HOST_DATA_DIR}"
   ```

### Problem: Container won't start - missing capabilities

**Symptoms:**
- Container exits immediately
- Logs show permission errors for `/dev/net/tun`

**Solutions:**

1. **Add required capabilities:**
   ```bash
   docker run \
     --cap-add=NET_ADMIN \
     --cap-add=SYS_MODULE \
     --device=/dev/net/tun \
     # ... other options
   ```

2. **For Docker Compose:**
   ```yaml
   cap_add:
     - NET_ADMIN
     - SYS_MODULE
   devices:
     - /dev/net/tun
   ```

### Problem: Port conflicts

**Symptoms:**
- Cannot access NZBGet WebUI
- Port already in use errors

**Solutions:**

1. **Change host port mapping:**
   ```bash
   # Use different host port
   -p 6790:6789  # Access via http://localhost:6790
   ```

2. **Check for port conflicts:**
   ```bash
   netstat -tuln | grep 6789
   lsof -i :6789
   ```

## 📡 NZBGet Issues

### Problem: NZBGet WebUI not accessible

**Solutions:**

1. **Verify container is running:**
   ```bash
   docker ps | grep nzbgetvpn
   ```

2. **Check port mapping:**
   ```bash
   docker port nzbgetvpn
   ```

3. **Access via container IP (troubleshooting):**
   ```bash
   docker inspect nzbgetvpn | grep IPAddress
   # Then try http://CONTAINER_IP:6789
   ```

4. **Check firewall rules:**
   ```bash
   # Ubuntu/Debian
   sudo ufw status
   
   # CentOS/RHEL
   sudo firewall-cmd --list-all
   ```

### Problem: Downloads fail or are very slow

**Solutions:**

1. **Check news server configuration:**
   - Verify correct hostname, port, and credentials
   - Check connection limits with your provider
   - Ensure SSL is enabled if required

2. **Test news server manually:**
   ```bash
   docker exec nzbgetvpn telnet your-news-server.com 563
   ```

3. **Adjust connection settings:**
   ```ini
   # Reduce connections if provider limits them
   NZBGET_S1_CONN=10
   
   # Or increase for higher speed (if allowed)
   NZBGET_S1_CONN=30
   ```

4. **Check disk space:**
   ```bash
   docker exec nzbgetvpn df -h /downloads
   ```

### Problem: Automated news server setup not working

**Symptoms:**
- NZBGet starts but Server1 is not configured
- Environment variables seem ignored

**Solutions:**

1. **Verify environment variables:**
   ```bash
   docker exec nzbgetvpn env | grep NZBGET_S1_
   ```

2. **Check script execution:**
   ```bash
   docker logs nzbgetvpn | grep "news-server"
   ```

3. **Ensure required variables are set:**
   ```ini
   # Minimum required
   NZBGET_S1_NAME=MyProvider
   NZBGET_S1_HOST=news.provider.com
   ```

## 🌐 Network Issues

### Problem: Cannot access from other devices on network

**Solutions:**

1. **Set LAN network correctly:**
   ```ini
   LAN_NETWORK=192.168.1.0/24
   ```

2. **Check Docker network settings:**
   ```bash
   docker network ls
   docker network inspect bridge
   ```

3. **Verify host firewall:**
   ```bash
   # Allow Docker networks
   sudo ufw allow from 172.16.0.0/12
   sudo ufw allow from 192.168.0.0/16
   ```

### Problem: IP leak detection

**Symptoms:**
- IP check shows your real IP instead of VPN IP
- Downloads appear to use your ISP connection

**Solutions:**

1. **Verify VPN is actually connected:**
   ```bash
   docker exec nzbgetvpn ip addr show tun0  # OpenVPN
   docker exec nzbgetvpn ip addr show wg0   # WireGuard
   ```

2. **Check routing table:**
   ```bash
   docker exec nzbgetvpn ip route
   ```

3. **Test kill switch:**
   ```bash
   # Stop VPN and see if downloads stop
   docker exec nzbgetvpn killall openvpn
   # Downloads should fail until VPN reconnects
   ```

## 🔍 Logging and Debugging

### Enable verbose logging

**For container startup issues:**
```ini
DEBUG=true
```

**For OpenVPN debugging:**
```ini
VPN_OPTIONS=--verb 4
```

**For NZBGet debugging:**
1. Access WebUI → Settings → Logging
2. Set LogLevel to "Detail" or "Debug"

### Useful log locations

```bash
# Container logs
docker logs nzbgetvpn

# NZBGet logs (inside container)
docker exec nzbgetvpn tail -f /config/nzbget.log

# OpenVPN logs (if available)
docker exec nzbgetvpn tail -f /var/log/openvpn.log
```

## 🆘 Common Error Messages

### "RTNETLINK answers: Operation not permitted"

**Cause:** Missing NET_ADMIN capability
**Solution:** Add `--cap-add=NET_ADMIN` to docker run or docker-compose

### "Cannot open TUN/TAP dev /dev/net/tun"

**Cause:** Missing device mapping
**Solution:** Add `--device=/dev/net/tun` to docker run or docker-compose

### "AUTH: Received control message: AUTH_FAILED"

**Cause:** Incorrect VPN credentials
**Solution:** Verify VPN_USER, VPN_PASS, or credentials file

### "RESOLVE: Cannot resolve host address"

**Cause:** DNS resolution issues
**Solution:** Set NAME_SERVERS environment variable

### "Permission denied (publickey)"

**Cause:** Wrong VPN authentication method
**Solution:** Check if provider requires certificates vs username/password

## 📞 Getting Help

If you're still experiencing issues:

1. **Search existing issues:** [GitHub Issues](https://github.com/magicalyak/nzbgetvpn/issues)

2. **Create a new issue:** Use the [Bug Report template](https://github.com/magicalyak/nzbgetvpn/issues/new?template=bug_report.yml)

3. **Include in your report:**
   - Full container logs: `docker logs nzbgetvpn`
   - Your configuration (redact sensitive info)
   - VPN provider and protocol used
   - Host OS and Docker version
   - Steps to reproduce the issue

4. **For questions:** Use the [Question template](https://github.com/magicalyak/nzbgetvpn/issues/new?template=question.yml)

## 📊 Monitoring & Auto-Restart Issues

### Problem: Monitoring server not accessible

**Symptoms:**
- Cannot access monitoring endpoints
- Monitoring port not responding

**Solutions:**

1. **Check if monitoring is enabled:**
   ```bash
   docker exec nzbgetvpn env | grep ENABLE_MONITORING
   ```

2. **Verify port mapping:**
   ```bash
   # Ensure you've mapped the monitoring port
   docker run -p 8080:8080 ...
   # or in docker-compose.yml:
   # ports:
   #   - "8080:8080"
   ```

3. **Check monitoring service status:**
   ```bash
   docker exec nzbgetvpn ps aux | grep monitoring-server
   ```

4. **View monitoring logs:**
   ```bash
   docker exec nzbgetvpn tail -f /config/monitoring.log
   ```

### Problem: Health checks showing "unknown" status ✅ FIXED

**This issue has been resolved in the current version.**

**What was fixed:**
- BusyBox compatibility issue with `grep -oP` command
- Status file creation now uses proper jq commands  
- News server check reads directly from NZBGet config file

**Expected behavior:**
```json
{
  "status": "healthy",
  "checks": {
    "nzbget": "success",
    "vpn_interface": "up", 
    "dns": "success",
    "news_server": "success"
  }
}
```

**If still seeing "unknown" values:**

1. **Test health endpoint:**
   ```bash
   curl http://localhost:8080/health
   ```

2. **Run health check manually:**
   ```bash
   docker exec nzbgetvpn /root/healthcheck.sh
   ```

3. **Check logs for errors:**
   ```bash
   docker exec nzbgetvpn tail -f /config/healthcheck.log
   ```

### Problem: Auto-restart not working

**Symptoms:**
- Services fail but don't restart automatically
- Auto-restart logs show errors

**Solutions:**

1. **Verify auto-restart is enabled:**
   ```bash
   docker exec nzbgetvpn env | grep ENABLE_AUTO_RESTART
   ```

2. **Check auto-restart service:**
   ```bash
   docker exec nzbgetvpn ps aux | grep auto-restart
   ```

3. **Review auto-restart logs:**
   ```bash
   docker exec nzbgetvpn tail -f /config/auto-restart.log
   ```

4. **Check restart attempt counters:**
   ```bash
   docker exec nzbgetvpn cat /tmp/vpn_restart_count
   docker exec nzbgetvpn cat /tmp/nzbget_restart_count
   ```

5. **Test manual restart:**
   ```bash
   # Test VPN restart capability
   docker exec nzbgetvpn bash /etc/cont-init.d/50-vpn-setup
   ```

### Problem: Webhook notifications not sending

**Solutions:**

1. **Verify webhook URL is set:**
   ```bash
   docker exec nzbgetvpn env | grep NOTIFICATION_WEBHOOK_URL
   ```

2. **Test webhook manually:**
   ```bash
   docker exec nzbgetvpn curl -X POST \
     -H "Content-Type: application/json" \
     -d '{"test": "message"}' \
     "${NOTIFICATION_WEBHOOK_URL}"
   ```

3. **Check for curl availability:**
   ```bash
   docker exec nzbgetvpn which curl
   ```

### Problem: Prometheus metrics not appearing

**Solutions:**

1. **Test Prometheus endpoint:**
   ```bash
   curl http://localhost:8080/prometheus
   ```

2. **Check metrics file:**
   ```bash
   docker exec nzbgetvpn cat /config/metrics.json
   ```

3. **Verify jq is available (for metrics processing):**
   ```bash
   docker exec nzbgetvpn which jq
   ```

## 🛠️ Advanced Troubleshooting

### Manual VPN testing

Test VPN outside the container to isolate issues:

```bash
# Test OpenVPN config directly
sudo openvpn --config /path/to/your/config.ovpn

# Test WireGuard config
sudo wg-quick up /path/to/your/config.conf
```

### Container network inspection

```bash
# Inspect container's network namespace
docker exec nzbgetvpn ip route
docker exec nzbgetvpn ip addr
docker exec nzbgetvpn iptables -L
```

### Performance monitoring

```bash
# Monitor container resources
docker stats nzbgetvpn

# Check network throughput
docker exec nzbgetvpn iftop

# Monitor download speed
docker exec nzbgetvpn tail -f /config/nzbget.log | grep "speed"
```

---

For more help, visit our [GitHub repository](https://github.com/magicalyak/nzbgetvpn) or check the [comprehensive README](README.md).

## 🏗️ Multi-Architecture Issues

### Problem: Wrong architecture pulled automatically

**Symptoms:**
- Container starts but performance is poor
- Unusual CPU usage patterns
- Platform detection shows emulation

**Solutions:**

1. **Force specific architecture:**
   ```bash
   # Explicitly specify platform
   docker pull --platform linux/arm64 magicalyak/nzbgetvpn:latest
   docker pull --platform linux/amd64 magicalyak/nzbgetvpn:latest
   ```

2. **Check current architecture:**
   ```bash
   docker exec nzbgetvpn /root/platform-info.sh --quiet
   docker exec nzbgetvpn uname -m
   ```

3. **Verify Docker buildx configuration:**
   ```bash
   docker buildx ls
   docker buildx inspect --bootstrap
   ```

### Problem: ARM64 performance issues (Raspberry Pi)

**Symptoms:**
- Slow download speeds
- High CPU usage
- Thermal throttling

**Solutions:**

1. **Check thermal status:**
   ```bash
   # Check CPU temperature
   docker exec nzbgetvpn cat /sys/class/thermal/thermal_zone0/temp
   # Should be < 70000 (70°C)
   
   # Check for throttling
   docker exec nzbgetvpn vcgencmd get_throttled
   # 0x0 = no throttling
   ```

2. **Optimize for ARM64:**
   ```ini
   # In .env file - ARM64 optimizations
   VPN_CLIENT=wireguard          # Better performance than OpenVPN
   NZBGET_S1_CONN=8             # Reduce connection count
   MONITORING_LOG_LEVEL=WARNING  # Reduce logging overhead
   ENABLE_AUTO_RESTART=true      # Recover from thermal issues
   ```

3. **System-level optimizations:**
   ```bash
   # Add cooling
   # Use SSD instead of SD card
   # Increase GPU memory split
   echo "gpu_mem=64" | sudo tee -a /boot/config.txt
   ```

### Problem: Apple Silicon Mac compatibility issues

**Solutions:**

1. **Verify ARM64 support:**
   ```bash
   # Check if running native ARM64
   docker exec nzbgetvpn uname -m
   # Should show: aarch64
   ```

2. **macOS-specific Docker settings:**
   ```bash
   # Increase Docker Desktop resources
   # Docker Desktop → Settings → Resources
   # Memory: 4GB+, CPU: 2+ cores
   ```

3. **File sharing optimization:**
   ```bash
   # Use bind mounts instead of named volumes for better performance
   -v ~/nzbgetvpn/config:/config
   -v ~/nzbgetvpn/downloads:/downloads
   ```

### Problem: AWS Graviton performance not optimal

**Solutions:**

1. **Instance optimization:**
   ```bash
   # Use Graviton3 instances (c7g, m7g, r7g)
   # Enable enhanced networking
   # Use GP3 EBS volumes for storage
   ```

2. **Network optimization:**
   ```ini
   # Cloud-optimized settings
   NZBGET_S1_CONN=20            # Higher connections work well in cloud
   VPN_CLIENT=wireguard         # Lower latency
   NAME_SERVERS=1.1.1.1,8.8.8.8 # Fast DNS
   ```

3. **Monitor instance metrics:**
   ```bash
   # Check CPU utilization
   docker stats nzbgetvpn
   
   # Monitor network throughput
   docker exec nzbgetvpn iftop
   ```

### Problem: NAS ARM64 compatibility issues

**Symptoms:**
- Container won't start on Synology/QNAP
- Permission errors on ARM-based NAS

**Solutions:**

1. **Check NAS architecture:**
   ```bash
   # SSH into NAS
   uname -m
   cat /proc/cpuinfo | grep -i arm
   ```

2. **NAS-specific configuration:**
   ```ini
   # Conservative settings for NAS
   NZBGET_S1_CONN=6             # Low connection count
   VPN_CLIENT=wireguard         # Better performance
   DEBUG=false                  # Reduce logging
   UMASK=000                    # NAS permission compatibility
   ```

3. **Use NAS-specific paths:**
   ```bash
   # Synology paths
   -v /volume1/docker/nzbgetvpn/config:/config
   -v /volume1/downloads:/downloads
   
   # QNAP paths
   -v /share/Container/nzbgetvpn/config:/config
   -v /share/downloads:/downloads
   ```

### Problem: Cross-compilation build failures

**Solutions:**

1. **Enable QEMU for cross-compilation:**
   ```bash
   docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
   ```

2. **Use buildx for multi-arch builds:**
   ```bash
   docker buildx create --name multiarch --driver docker-container --use
   docker buildx build --platform linux/amd64,linux/arm64 -t test .
   ```

3. **Check available platforms:**
   ```bash
   docker buildx ls
   docker buildx inspect --bootstrap
   ```

### Problem: Platform detection failures

**Solutions:**

1. **Manual platform override:**
   ```bash
   # Force platform in environment
   docker run -e TARGETARCH=arm64 ...
   docker run -e TARGETARCH=amd64 ...
   ```

2. **Debug platform detection:**
   ```bash
   docker exec nzbgetvpn /root/platform-info.sh --json
   docker exec nzbgetvpn env | grep -E "(TARGET|BUILD|PLATFORM)"
   ```

### Problem: Performance differences between architectures

**Expected performance characteristics:**

| Architecture | Typical Performance | Optimization Focus |
|--------------|-------------------|-------------------|
| AMD64 | High throughput, parallel processing | Connection count, encryption |
| ARM64 | Power efficiency, moderate throughput | Thermal management, connection limits |

**Optimization strategies:**

1. **AMD64 optimization:**
   ```ini
   NZBGET_S1_CONN=20-30
   VPN_OPTIONS=--fast-io
   MONITORING_LOG_LEVEL=DEBUG
   ```

2. **ARM64 optimization:**
   ```ini
   NZBGET_S1_CONN=6-12
   VPN_CLIENT=wireguard
   MONITORING_LOG_LEVEL=INFO
   ENABLE_AUTO_RESTART=true
   ```

## 🛠️ Advanced Multi-Architecture Debugging

### Platform-specific diagnostics

```bash
# Complete platform diagnostic
docker exec nzbgetvpn /root/platform-info.sh

# Check architecture-specific optimizations
docker exec nzbgetvpn env | grep -E "(ARM|AMD|PLATFORM)"

# Monitor resource usage by architecture
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

# Architecture-specific performance test
docker exec nzbgetvpn sysbench cpu --cpu-max-prime=20000 run
```

### Multi-architecture build testing

```bash
# Test current platform
docker run --rm magicalyak/nzbgetvpn:latest /root/platform-info.sh --quiet

# Test specific platform
docker run --rm --platform linux/arm64 magicalyak/nzbgetvpn:latest /root/platform-info.sh --quiet
docker run --rm --platform linux/amd64 magicalyak/nzbgetvpn:latest /root/platform-info.sh --quiet

# Compare performance
time docker run --rm --platform linux/arm64 magicalyak/nzbgetvpn:latest python3 -c "import time; time.sleep(1)"
time docker run --rm --platform linux/amd64 magicalyak/nzbgetvpn:latest python3 -c "import time; time.sleep(1)"
```

---

For more help, visit our [GitHub repository](https://github.com/magicalyak/nzbgetvpn) or check the:
- **[README](README.md)** for general usage
- **[MULTI-ARCH.md](MULTI-ARCH.md)** for detailed platform guides  
- **[MONITORING.md](MONITORING.md)** for monitoring setup 