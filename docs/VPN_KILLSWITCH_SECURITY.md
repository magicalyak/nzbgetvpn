# Enhanced VPN Kill Switch Security Features

## Overview

This document describes the enhanced VPN kill switch security features implemented in the NZBGetVPN container. These features provide comprehensive protection against data leaks and ensure that NZBGet traffic only flows through the VPN connection.

## Key Security Improvements

### 1. Strict Default DROP Policy

The container now implements a strict deny-all approach with default DROP policies on all iptables chains:

- **INPUT**: DROP (blocks all incoming connections except explicitly allowed)
- **FORWARD**: DROP (blocks all forwarded traffic)
- **OUTPUT**: DROP (blocks all outgoing connections except explicitly allowed)

This ensures that no traffic can leak outside the VPN tunnel unless explicitly permitted.

### 2. DNS Leak Prevention

DNS queries are strictly controlled to prevent DNS leaks:

- All DNS traffic (port 53 UDP/TCP) on eth0 is **blocked**
- DNS queries are only allowed through the VPN interface
- This prevents your ISP from seeing your DNS queries

### 3. Active VPN Monitoring Service

A dedicated monitoring service (`vpn-monitor`) continuously checks VPN health:

- Monitors VPN interface status every 30 seconds (configurable)
- Verifies interface exists, is UP, has an IP address, and routing
- Automatically stops NZBGet if VPN connection fails
- Enforces strict killswitch rules when VPN is down

### 4. Automatic Service Protection

If the VPN fails:

1. NZBGet is immediately stopped to prevent data leaks
2. All new outgoing connections are blocked
3. Only established connections are allowed to finish
4. A flag file prevents NZBGet from restarting until VPN is restored

## Configuration Options

### Environment Variables

```bash
# VPN Monitoring
VPN_CHECK_INTERVAL=30        # Seconds between VPN health checks (default: 30)
VPN_MAX_FAILURES=3          # Consecutive failures before action (default: 3)
CHECK_DNS=true              # Enable DNS resolution testing (default: false)
CHECK_EXTERNAL_IP=true      # Check external IP through VPN (default: false)
AUTO_RESTART_VPN=true       # Automatically restart VPN on failure (default: false)

# Debug Options
DEBUG=true                  # Enable verbose logging and iptables packet logging
```

### Docker Compose Example

```yaml
version: '3.8'

services:
  nzbgetvpn:
    image: magicalyak/nzbgetvpn:latest
    container_name: nzbgetvpn
    cap_add:
      - NET_ADMIN
    environment:
      - VPN_CLIENT=openvpn
      - VPN_CHECK_INTERVAL=20
      - VPN_MAX_FAILURES=2
      - CHECK_DNS=true
      - AUTO_RESTART_VPN=true
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    ports:
      - "6789:6789"  # NZBGet WebUI
      - "8080:8080"  # Monitoring port
    restart: unless-stopped
```

## Security Architecture

### Traffic Flow

1. **Incoming Traffic**: Only allowed on specific ports (6789 for NZBGet UI, 8080 for monitoring)
2. **Outgoing Traffic**:
   - VPN tunnel: All allowed
   - eth0: Only VPN connection establishment and LAN (if configured)
   - DNS: Only through VPN interface

### Kill Switch Enforcement Layers

1. **Layer 1**: Default DROP policies on all chains
2. **Layer 2**: DNS leak prevention rules
3. **Layer 3**: Active VPN monitoring with automatic service shutdown
4. **Layer 4**: Packet logging for blocked traffic (when DEBUG=true)

## Monitoring and Troubleshooting

### Check VPN Status

```bash
# View VPN monitoring logs
docker exec nzbgetvpn cat /tmp/vpn-monitor.log

# Check killswitch status
docker exec nzbgetvpn iptables -L -n -v

# View blocked traffic (requires DEBUG=true)
docker exec nzbgetvpn dmesg | grep KILLSWITCH-BLOCKED
```

### Alert Files

- `/tmp/vpn_monitor_alerts.log`: Contains all VPN monitoring alerts
- `/tmp/vpn_failed_nzbget_stopped`: Present when NZBGet is stopped due to VPN failure
- `/tmp/vpn_killswitch_active`: Indicates killswitch is active

### Service Status

```bash
# Check VPN monitor service
docker exec nzbgetvpn s6-svstat /var/run/s6/services/vpn-monitor

# Check NZBGet service
docker exec nzbgetvpn s6-svstat /var/run/s6/services/nzbget
```

## Testing the Kill Switch

### Manual VPN Failure Test

1. Access the container:
   ```bash
   docker exec -it nzbgetvpn /bin/bash
   ```

2. Simulate VPN failure:
   ```bash
   # For OpenVPN
   s6-svc -d /var/run/s6/services/openvpn

   # For WireGuard
   wg-quick down wg0
   ```

3. Observe:
   - NZBGet should stop within `VPN_CHECK_INTERVAL * VPN_MAX_FAILURES` seconds
   - All new outgoing traffic should be blocked
   - Check logs at `/tmp/vpn-monitor.log`

### DNS Leak Test

1. With VPN connected, test DNS:
   ```bash
   docker exec nzbgetvpn nslookup google.com
   ```

2. Stop VPN and test again - DNS should fail:
   ```bash
   docker exec nzbgetvpn ip link set tun0 down
   docker exec nzbgetvpn nslookup google.com  # Should fail
   ```

## Security Best Practices

1. **Regular Updates**: Keep the container image updated for latest security patches
2. **Strong VPN Provider**: Use a reputable VPN provider with no-logs policy
3. **Monitor Logs**: Regularly check monitoring logs for VPN failures
4. **Test Kill Switch**: Periodically test the kill switch functionality
5. **Minimize Exposed Ports**: Only expose necessary ports to the host

## Troubleshooting Common Issues

### NZBGet Won't Start

- Check VPN connection: `docker exec nzbgetvpn ip addr show tun0`
- Check for flag file: `docker exec nzbgetvpn ls -la /tmp/vpn_failed_nzbget_stopped`
- Review VPN logs: `docker exec nzbgetvpn cat /tmp/vpn-setup.log`

### VPN Connects but NZBGet Stops

- Increase `VPN_MAX_FAILURES` if VPN is unstable
- Check DNS configuration in VPN config
- Review monitor logs: `docker exec nzbgetvpn cat /tmp/vpn-monitor.log`

### Cannot Access NZBGet UI

- Verify port mapping in docker-compose
- Check iptables rules: `docker exec nzbgetvpn iptables -L INPUT -n -v`
- Ensure policy routing is active: `docker exec nzbgetvpn ip rule list`

## Conclusion

These enhanced security features provide multiple layers of protection to ensure your NZBGet traffic remains private and secure. The combination of strict iptables rules, DNS leak prevention, and active VPN monitoring creates a robust kill switch that prevents data leaks even in case of VPN failure.