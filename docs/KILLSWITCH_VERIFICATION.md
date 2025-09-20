# VPN Kill Switch Verification Guide

This guide provides multiple methods to verify that the VPN kill switch is working correctly and protecting your privacy.

## Automated Testing

Run the provided test script:

```bash
# Basic test
./test-killswitch.sh nzbgetvpn

# Verbose output with debugging
./test-killswitch.sh nzbgetvpn true
```

## Manual Verification Methods

### Method 1: Check IPTables Rules

Verify that strict DROP policies are in place:

```bash
# Check default policies
docker exec nzbgetvpn iptables -L -n | head -10
```

Expected output:
```
Chain INPUT (policy DROP)
Chain FORWARD (policy DROP)
Chain OUTPUT (policy DROP)
```

### Method 2: DNS Leak Test

1. Check that DNS is blocked on eth0:
```bash
docker exec nzbgetvpn iptables -L OUTPUT -n -v | grep "dpt:53"
```

You should see:
- DROP rules for port 53 on eth0
- ACCEPT rules for port 53 on tun0/wg0

2. Test DNS resolution:
```bash
# This should work (through VPN)
docker exec nzbgetvpn nslookup google.com

# Simulate VPN down - DNS should fail
docker exec nzbgetvpn ip link set tun0 down
docker exec nzbgetvpn nslookup google.com  # Should fail
docker exec nzbgetvpn ip link set tun0 up   # Restore
```

### Method 3: VPN Failure Simulation

1. Monitor NZBGet status:
```bash
# Check if NZBGet is running
docker exec nzbgetvpn pgrep nzbget
```

2. Simulate VPN failure:
```bash
# Stop VPN interface
docker exec nzbgetvpn ip link set tun0 down

# Wait 90 seconds (based on default check interval)
sleep 90

# Check if NZBGet stopped
docker exec nzbgetvpn pgrep nzbget  # Should return nothing

# Check for stop flag
docker exec nzbgetvpn ls -la /tmp/vpn_failed_nzbget_stopped
```

3. Restore VPN:
```bash
docker exec nzbgetvpn ip link set tun0 up
```

### Method 4: External IP Check

Verify all traffic goes through VPN:

```bash
# Get container's external IP
docker exec nzbgetvpn curl -s https://api.ipify.org

# Compare with your real IP
curl -s https://api.ipify.org
```

These should be different - the container should show your VPN provider's IP.

### Method 5: Traffic Analysis

Monitor network traffic to ensure no leaks:

```bash
# Install tcpdump in container (if not present)
docker exec nzbgetvpn apk add --no-cache tcpdump

# Monitor eth0 for non-allowed traffic
docker exec nzbgetvpn tcpdump -i eth0 -n 'not port 6789 and not port 8080 and not arp'
```

While monitoring, try to generate traffic:
```bash
docker exec nzbgetvpn curl http://example.com
```

You should see NO packets on eth0 (except for allowed ports).

### Method 6: Monitor Service Check

Verify the VPN monitor is running:

```bash
# Check service status
docker exec nzbgetvpn s6-svstat /var/run/s6/services/vpn-monitor

# View monitor logs
docker exec nzbgetvpn tail -f /tmp/vpn-monitor.log

# Check for alerts
docker exec nzbgetvpn cat /tmp/vpn_monitor_alerts.log
```

### Method 7: Firewall Log Analysis

If DEBUG=true, check blocked packets:

```bash
# View kernel messages for blocked packets
docker exec nzbgetvpn dmesg | grep "KILLSWITCH-BLOCKED"
```

## Expected Behavior

When the kill switch is working correctly:

1. ✅ **All traffic blocked by default** - Only explicitly allowed traffic passes
2. ✅ **DNS only through VPN** - No DNS queries on eth0
3. ✅ **NZBGet auto-stops** - Service halts if VPN fails
4. ✅ **No traffic leaks** - eth0 only allows UI access and VPN establishment
5. ✅ **Monitoring active** - Continuous health checks running
6. ✅ **Automatic recovery** - NZBGet restarts when VPN restored

## Common Test Scenarios

### Scenario 1: VPN Provider Maintenance

```bash
# Simulate by blocking VPN server
docker exec nzbgetvpn iptables -I OUTPUT 1 -d <vpn-server-ip> -j DROP

# Wait and verify NZBGet stops
sleep 90
docker exec nzbgetvpn pgrep nzbget  # Should be empty

# Restore
docker exec nzbgetvpn iptables -D OUTPUT 1
```

### Scenario 2: DNS Leak Prevention

```bash
# Try to use a different DNS server on eth0
docker exec nzbgetvpn dig @8.8.8.8 google.com

# Should timeout or fail
```

### Scenario 3: Connection Interruption

```bash
# Kill OpenVPN process
docker exec nzbgetvpn pkill openvpn

# Monitor should detect and stop NZBGet
sleep 90
docker exec nzbgetvpn ls /tmp/vpn_failed_nzbget_stopped
```

## Continuous Monitoring

Set up a monitoring script on your host:

```bash
#!/bin/bash
# monitor-killswitch.sh

while true; do
    # Check VPN status
    VPN_UP=$(docker exec nzbgetvpn ip link show tun0 2>/dev/null | grep "state UP" | wc -l)

    # Check NZBGet status
    NZBGET_UP=$(docker exec nzbgetvpn pgrep nzbget | wc -l)

    # Check for leak flag
    LEAK_FLAG=$(docker exec nzbgetvpn ls /tmp/vpn_failed_nzbget_stopped 2>/dev/null | wc -l)

    echo "$(date): VPN=$VPN_UP NZBGet=$NZBGET_UP LeakProtection=$LEAK_FLAG"

    # Alert if inconsistent state
    if [ "$VPN_UP" -eq 0 ] && [ "$NZBGET_UP" -gt 0 ]; then
        echo "WARNING: NZBGet running without VPN!"
    fi

    sleep 30
done
```

## Troubleshooting Failed Tests

### If DNS still leaks:
```bash
# Check DNS rules specifically
docker exec nzbgetvpn iptables -L OUTPUT -n -v | grep 53
```

### If NZBGet doesn't stop:
```bash
# Check monitor service
docker exec nzbgetvpn s6-svstat /var/run/s6/services/vpn-monitor

# Check environment variables
docker exec nzbgetvpn env | grep VPN_
```

### If traffic leaks on eth0:
```bash
# List all OUTPUT rules
docker exec nzbgetvpn iptables -L OUTPUT -n -v --line-numbers
```

## Security Certification

After running all tests successfully, you can be confident that:

1. Your real IP is never exposed
2. DNS queries don't leak to your ISP
3. Downloads stop immediately if VPN fails
4. No data can leak outside the VPN tunnel
5. The system self-heals when VPN is restored

This multi-layered approach ensures maximum privacy protection for your NZBGet downloads.