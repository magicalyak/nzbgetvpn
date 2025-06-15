# Home Assistant Integration for nzbgetvpn

This directory contains Home Assistant configuration files for monitoring your nzbgetvpn container with comprehensive health checks and beautiful dashboards.

## 🎯 **Features**

### **📊 Comprehensive Monitoring**
- ✅ **Real-time health status** with color-coded indicators
- ✅ **Individual health checks** (NZBGet, VPN, DNS, News Server)
- ✅ **Security monitoring** (IP leak detection, DNS leak detection)
- ✅ **System metrics** (CPU, memory, load average, uptime)
- ✅ **VPN status tracking** (interface status, connectivity, external IP)

### **🔔 Smart Notifications**
- ✅ **Health alerts** when container becomes unhealthy
- ✅ **VPN disconnection alerts** with immediate notifications
- ✅ **IP leak detection** with critical priority alerts
- ✅ **Configurable alert delays** to prevent false positives

### **🎨 Beautiful Dashboards**
- ✅ **Professional Lovelace cards** with state-based coloring
- ✅ **Historical graphs** showing health trends over time
- ✅ **Quick action buttons** for common tasks
- ✅ **Mobile-friendly design** that works on all devices

## 🚀 **Quick Setup**

### **Step 1: Configure Sensors**

Add the sensor configuration to your `configuration.yaml`:

```yaml
# Copy content from configuration.yaml
sensor:
  - platform: rest
    name: nzbgetvpn_health
    resource: http://rocky.gamull.com:8080/health
    scan_interval: 30
    # ... (see configuration.yaml for full config)
```

### **Step 2: Add Lovelace Card**

Choose one of the dashboard options:

#### **Option A: Simple Dashboard** (Recommended)
```yaml
# Copy content from simple-lovelace.yaml
type: vertical-stack
cards:
  - type: glance
    title: "🛡️ nzbgetvpn Status Monitor"
    # ... (see simple-lovelace.yaml for full config)
```

#### **Option B: Advanced Dashboard** (Requires custom cards)
```yaml
# Copy content from nzbgetvpn-lovelace.yaml
# Requires: card-mod, bar-card custom components
```

### **Step 3: Restart Home Assistant**

```bash
# Restart Home Assistant to load new sensors
sudo systemctl restart home-assistant
# or use the UI: Settings > System > Restart
```

## 📋 **Prerequisites**

### **Required**
- ✅ **Home Assistant** (2023.1 or later)
- ✅ **nzbgetvpn container** with enhanced monitoring enabled
- ✅ **Network access** from Home Assistant to nzbgetvpn monitoring port (8080)

### **Optional (for advanced dashboard)**
- 🎨 **card-mod** - For custom styling
- 📊 **bar-card** - For progress bars
- 🔔 **Mobile app** - For push notifications

Install custom components via HACS:
```
HACS > Frontend > Search for "card-mod" > Install
HACS > Frontend > Search for "bar-card" > Install
```

## 🔧 **Configuration Options**

### **Sensor Customization**

Update the resource URLs in `configuration.yaml`:

```yaml
sensor:
  - platform: rest
    name: nzbgetvpn_health
    resource: http://YOUR_SERVER:8080/health  # Update this
    scan_interval: 30  # Adjust polling frequency
```

### **Notification Customization**

Update notification services in the automation section:

```yaml
automation:
  - alias: "nzbgetvpn Health Alert"
    action:
      - service: notify.YOUR_NOTIFICATION_SERVICE  # Update this
        data:
          title: "🚨 nzbgetvpn Alert"
          # ... customize message
```

### **Dashboard Customization**

Modify the Lovelace cards to match your preferences:

```yaml
# Change colors, icons, or layout
- type: glance
  title: "Your Custom Title"
  entities:
    # Add/remove entities as needed
```

## 📊 **Available Sensors**

### **Main Sensors**
| Sensor | Description | Values |
|--------|-------------|--------|
| `sensor.nzbgetvpn_health` | Overall health status | healthy, warning, degraded, unhealthy |
| `sensor.nzbgetvpn_external_ip` | Current external IP | IP address |
| `sensor.nzbgetvpn_uptime` | Container uptime | Human readable time |

### **Health Check Sensors**
| Sensor | Description | Values |
|--------|-------------|--------|
| `sensor.nzbgetvpn_nzbget_status` | NZBGet connectivity | success, failed |
| `sensor.nzbgetvpn_vpn_interface` | VPN interface status | up, down, missing |
| `sensor.nzbgetvpn_vpn_connectivity` | VPN connectivity test | success, failed |
| `sensor.nzbgetvpn_dns_status` | DNS resolution | success, failed |
| `sensor.nzbgetvpn_news_server` | News server connectivity | success, failed |
| `sensor.nzbgetvpn_ip_leak` | IP leak detection | stable, changed |
| `sensor.nzbgetvpn_dns_leak` | DNS leak detection | stable, changed |

### **System Metrics**
| Sensor | Description | Unit |
|--------|-------------|------|
| `sensor.nzbgetvpn_memory_usage` | Memory usage percentage | % |
| `sensor.nzbgetvpn_cpu_usage` | CPU usage percentage | % |
| `sensor.nzbgetvpn_load_average` | System load average | number |

### **Binary Sensors**
| Sensor | Description | States |
|--------|-------------|--------|
| `binary_sensor.nzbgetvpn_healthy` | Overall health | on/off |
| `binary_sensor.nzbgetvpn_nzbget_ok` | NZBGet status | on/off |
| `binary_sensor.nzbgetvpn_vpn_ok` | VPN status | on/off |

## 🔔 **Notification Examples**

### **Discord Webhook**
```yaml
automation:
  - alias: "nzbgetvpn Health Alert"
    action:
      - service: notify.discord
        data:
          message: "🚨 nzbgetvpn is unhealthy!"
```

### **Telegram**
```yaml
automation:
  - alias: "nzbgetvpn Health Alert"
    action:
      - service: notify.telegram
        data:
          message: "🚨 nzbgetvpn container health alert!"
```

### **Mobile App**
```yaml
automation:
  - alias: "nzbgetvpn Health Alert"
    action:
      - service: notify.mobile_app_your_phone
        data:
          title: "🚨 nzbgetvpn Alert"
          message: "Container is unhealthy!"
          data:
            priority: high
```

## 🎨 **Dashboard Examples**

### **Simple Status Card**
```yaml
type: entities
title: "nzbgetvpn Quick Status"
entities:
  - sensor.nzbgetvpn_health
  - sensor.nzbgetvpn_external_ip
  - binary_sensor.nzbgetvpn_vpn_ok
```

### **Detailed Health Grid**
```yaml
type: glance
title: "Health Checks"
entities:
  - binary_sensor.nzbgetvpn_nzbget_ok
  - binary_sensor.nzbgetvpn_vpn_ok
  - sensor.nzbgetvpn_dns_status
  - sensor.nzbgetvpn_ip_leak
state_color: true
```

## 🔧 **Troubleshooting**

### **Sensors Show "Unknown"**
```bash
# Check if nzbgetvpn monitoring is running
curl http://rocky.gamull.com:8080/health

# Check Home Assistant logs
tail -f /config/home-assistant.log | grep nzbgetvpn
```

### **No Data in Dashboard**
1. **Verify sensor configuration** in `configuration.yaml`
2. **Check network connectivity** from Home Assistant to nzbgetvpn
3. **Restart Home Assistant** after configuration changes
4. **Check entity names** in Lovelace configuration

### **Notifications Not Working**
1. **Verify notification service** is configured correctly
2. **Test notification service** manually
3. **Check automation triggers** and conditions
4. **Review Home Assistant logs** for errors

## 📚 **Additional Resources**

- **[nzbgetvpn Health Check Options](../../HEALTHCHECK_OPTIONS.md)** - Complete health check configuration
- **[Monitoring Setup Guide](../docs/MONITORING_SETUP.md)** - Comprehensive monitoring setup
- **[Home Assistant REST Sensor](https://www.home-assistant.io/integrations/rest/)** - Official documentation
- **[Home Assistant Automations](https://www.home-assistant.io/docs/automation/)** - Automation guide

## 🎯 **Example Dashboard Screenshot**

When properly configured, your dashboard will show:

```
🛡️ nzbgetvpn Status Monitor
┌─────────────┬─────────────┬─────────────┬─────────────┐
│   healthy   │ 203.0.113.42│    tun0     │  2d 14h 32m │
│ (Overall)   │(External IP)│(VPN Interface)│  (Uptime)  │
└─────────────┴─────────────┴─────────────┴─────────────┘

🔍 Health Checks
┌─────┬─────┬─────────────┬─────┬──────────┬─────────┐
│ ✅  │ ✅  │     ✅      │ ✅  │    ✅    │   ✅    │
│NZBGet│ VPN │VPN Connect. │ DNS │News Server│IP Leak │
└─────┴─────┴─────────────┴─────┴──────────┴─────────┘

📊 System Resources
Memory Usage: 45.2% ████████████░░░░░░░░░░░░░░░░
CPU Usage: 12.8% ███░░░░░░░░░░░░░░░░░░░░░░░░░░░
Load Average: 0.34
```

This provides a comprehensive, at-a-glance view of your nzbgetvpn container's health and performance! 