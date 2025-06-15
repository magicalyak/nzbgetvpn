# NZBGetVPN Healthcheck Options

Enhanced health checking for NZBGetVPN with **comprehensive monitoring** of VPN, NZBGet, and network connectivity.

## 🎯 **Overview**

The enhanced healthcheck system provides multiple configurable checks to ensure your NZBGetVPN container is operating correctly. Unlike basic health checks that only verify if the container is running, these checks monitor:

- ✅ **NZBGet responsiveness** (web interface + JSON-RPC)
- ✅ **VPN interface status** (up/down/missing)
- ✅ **VPN connectivity** (actual network testing)
- ✅ **DNS resolution** (prevent DNS leaks)
- ✅ **News server connectivity** (Usenet server access)
- ✅ **IP leak detection** (monitor IP changes)
- ✅ **DNS leak detection** (monitor DNS server changes)
- ✅ **System metrics** (memory, CPU, disk, network)

## 🔧 **Configuration Options**

All health checks can be customized using environment variables:

### **Core Health Check Settings**

| Variable | Default | Description |
|----------|---------|-------------|
| `HEALTH_CHECK_HOST` | `google.com` | Host to use for connectivity and DNS tests |
| `HEALTH_CHECK_TIMEOUT` | `10` | Timeout in seconds for health check operations |
| `EXTERNAL_IP_SERVICE` | `ifconfig.me` | Service to use for external IP detection |

### **Check Enable/Disable Flags**

| Variable | Default | Description |
|----------|---------|-------------|
| `CHECK_VPN_CONNECTIVITY` | `true` | Test actual VPN connectivity via ping |
| `CHECK_NEWS_SERVER` | `true` | Test connectivity to configured news server |
| `CHECK_DNS_LEAK` | `false` | Monitor DNS server changes |
| `CHECK_IP_LEAK` | `false` | Monitor external IP changes |

### **Monitoring & Metrics**

| Variable | Default | Description |
|----------|---------|-------------|
| `METRICS_ENABLED` | `false` | Enable detailed metrics collection |
| `DEBUG` | `false` | Enable verbose logging for troubleshooting |

## 🚀 **Quick Setup Examples**

### **Basic Setup (Default)**
```yaml
# docker-compose.yml
version: "3.8"
services:
  nzbgetvpn:
    image: magicalyak/nzbgetvpn:latest
    container_name: nzbgetvpn
    # Default healthcheck runs every 30s
    # Only essential checks: NZBGet + VPN interface + News server
```

### **Enhanced Monitoring Setup**
```yaml
# docker-compose.yml
version: "3.8"
services:
  nzbgetvpn:
    image: magicalyak/nzbgetvpn:latest
    container_name: nzbgetvpn
    environment:
      # Enable comprehensive monitoring
      - METRICS_ENABLED=true
      - CHECK_VPN_CONNECTIVITY=true
      - CHECK_DNS_LEAK=true
      - CHECK_IP_LEAK=true
      
      # Customize check behavior
      - HEALTH_CHECK_HOST=cloudflare.com
      - HEALTH_CHECK_TIMEOUT=15
      - EXTERNAL_IP_SERVICE=icanhazip.com
```

### **Security-Focused Setup**
```yaml
# docker-compose.yml
version: "3.8"
services:
  nzbgetvpn:
    image: magicalyak/nzbgetvpn:latest
    container_name: nzbgetvpn
    environment:
      # Enable all security checks
      - CHECK_DNS_LEAK=true
      - CHECK_IP_LEAK=true
      - CHECK_VPN_CONNECTIVITY=true
      - METRICS_ENABLED=true
      
      # Enable debug logging for security analysis
      - DEBUG=true
```

### **Development/Testing Setup**
```yaml
# docker-compose.yml
version: "3.8"
services:
  nzbgetvpn:
    image: magicalyak/nzbgetvpn:latest
    container_name: nzbgetvpn
    environment:
      # Disable non-critical checks for development
      - CHECK_NEWS_SERVER=false
      - CHECK_VPN_CONNECTIVITY=false
      - CHECK_DNS_LEAK=false
      - CHECK_IP_LEAK=false
      
      # Quick health checks
      - HEALTH_CHECK_TIMEOUT=5
```

## 📊 **Health Check Status Levels**

The healthcheck system returns different status levels based on the severity of issues:

| Status | Description | Exit Code | Container State |
|--------|-------------|-----------|-----------------|
| **healthy** | All checks passed | `0` | Running (green) |
| **warning** | Non-critical issues (news server, IP changes) | `6-8` | Running (yellow) |
| **degraded** | Important issues (DNS, VPN connectivity) | `4-5` | Running (orange) |
| **unhealthy** | Critical issues (NZBGet down, VPN interface down) | `1-3` | Unhealthy (red) |

### **Detailed Exit Codes**

| Code | Issue | Severity | Description |
|------|-------|----------|-------------|
| `0` | None | ✅ Healthy | All systems operational |
| `1` | NZBGet not responding | 🔴 Critical | NZBGet web interface down |
| `2` | VPN interface down | 🔴 Critical | VPN interface exists but is down |
| `3` | VPN interface missing | 🔴 Critical | No VPN interface found |
| `4` | VPN connectivity failed | 🟠 Degraded | VPN interface up but no connectivity |
| `5` | DNS resolution failed | 🟠 Degraded | Cannot resolve DNS queries |
| `6` | News server failed | 🟡 Warning | Cannot connect to news server |
| `7` | IP leak detected | 🟡 Warning | External IP changed |
| `8` | DNS leak detected | 🟡 Warning | DNS servers changed |

## 🔍 **Testing Your Configuration**

### **Manual Health Check**
```bash
# Run health check manually
docker exec nzbgetvpn /root/healthcheck.sh
echo "Exit code: $?"

# Check health status
docker exec nzbgetvpn cat /tmp/nzbgetvpn_status.json | jq '.'

# View health logs
docker exec nzbgetvpn tail -20 /config/healthcheck.log
```

### **Monitor Health Status**
```bash
# Watch container health status
watch 'docker ps --format "table {{.Names}}\t{{.Status}}"'

# Monitor health check logs in real-time
docker exec nzbgetvpn tail -f /config/healthcheck.log
```

### **Test Specific Checks**
```bash
# Test external IP detection
docker exec nzbgetvpn curl -s ifconfig.me

# Test DNS resolution
docker exec nzbgetvpn nslookup google.com

# Test VPN interface
docker exec nzbgetvpn ip link show tun0  # or wg0 for WireGuard

# Test NZBGet connectivity
docker exec nzbgetvpn curl -sSf http://localhost:6789
```

## 🔧 **Customization Examples**

### **Custom Health Check Host**
```bash
# Use Cloudflare instead of Google for connectivity tests
HEALTH_CHECK_HOST=1.1.1.1
```

### **Custom External IP Service**
```bash
# Use different IP detection service
EXTERNAL_IP_SERVICE=ip.me
# or
EXTERNAL_IP_SERVICE=ipecho.net/plain
```

### **Increased Timeouts for Slow Networks**
```bash
# Increase timeout for slow connections
HEALTH_CHECK_TIMEOUT=30
```

## 📈 **Metrics and Monitoring**

When `METRICS_ENABLED=true`, the system collects detailed metrics:

### **Available Metrics**
- **Response times** for all health checks
- **Success rates** over time
- **System resource usage** (CPU, memory, disk)
- **Network statistics** (bytes sent/received)
- **VPN interface statistics** (if available)
- **External IP tracking**
- **DNS server tracking**

### **Accessing Metrics**
```bash
# JSON metrics endpoint
curl http://localhost:8080/metrics

# Prometheus metrics endpoint
curl http://localhost:8080/prometheus

# Health status endpoint
curl http://localhost:8080/health

# Detailed status endpoint
curl http://localhost:8080/status
```

## 🚨 **Troubleshooting**

### **Container Constantly Restarting**
```bash
# Check which health check is failing
docker logs nzbgetvpn | grep -i error

# Disable problematic checks temporarily
echo "CHECK_VPN_CONNECTIVITY=false" >> .env
docker restart nzbgetvpn
```

### **False Positive Health Check Failures**
```bash
# Enable debug logging
echo "DEBUG=true" >> .env
docker restart nzbgetvpn

# Check detailed logs
docker exec nzbgetvpn tail -50 /config/healthcheck.log
```

### **VPN Interface Detection Issues**
```bash
# Check which VPN interfaces exist
docker exec nzbgetvpn ip link show

# Check VPN interface file
docker exec nzbgetvpn cat /tmp/vpn_interface_name

# Manually set VPN interface
docker exec nzbgetvpn echo "tun0" > /tmp/vpn_interface_name
```

## 🔐 **Security Considerations**

### **IP Leak Detection**
When `CHECK_IP_LEAK=true`:
- Monitors your external IP address
- Logs any changes (potential VPN disconnections)
- Stores previous IP for comparison

### **DNS Leak Detection**
When `CHECK_DNS_LEAK=true`:
- Monitors which DNS servers are being used
- Logs any changes (potential DNS leaks)
- Helps ensure DNS queries go through VPN

### **VPN Connectivity Testing**
When `CHECK_VPN_CONNECTIVITY=true`:
- Actively tests network connectivity through VPN interface
- Verifies VPN tunnel is actually working
- Uses ping tests to configured host

## 📋 **Best Practices**

1. **Start with defaults** - Test basic functionality first
2. **Enable monitoring gradually** - Add checks one at a time
3. **Monitor logs** - Check `/config/healthcheck.log` regularly
4. **Use appropriate timeouts** - Adjust based on your network speed
5. **Consider your setup** - Some checks may not be needed in all environments

## 🆘 **Getting Help**

If you encounter issues:

1. **Enable debug logging**: `DEBUG=true`
2. **Check logs**: `docker exec nzbgetvpn tail -50 /config/healthcheck.log`
3. **Test manually**: Run individual curl/ping commands
4. **Check configuration**: Verify environment variables are set correctly
5. **Create GitHub issue**: Include logs and configuration details 