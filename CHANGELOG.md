# Changelog

All notable changes to nzbgetvpn will be documented in this file.

## [v25.0.33] - 2025-01-27

### 🧹 Repository Consolidation & Cleanup
- **Eliminated Documentation Redundancy**: Removed redundant `MONITORING.md` from root
  - Consolidated monitoring documentation into comprehensive guide
  - Updated all references to point to `monitoring/docs/MONITORING_SETUP.md`
  - Streamlined documentation hierarchy for better user experience

### 🗂️ File Structure Optimization
- **Removed System Files**: Cleaned up `.DS_Store` files and improved `.gitignore`
  - Added macOS system files, Thumbs.db, and other OS artifacts to `.gitignore`
  - Removed committed system files from repository
- **Removed Unused Development Data**: Cleaned up `test_data/` directory
  - Removed leftover development artifacts not referenced anywhere
  - Reduced repository size and complexity

### 📚 Enhanced Documentation Structure
- **Streamlined Monitoring Guides**: Improved documentation hierarchy
  - `monitoring/README.md` - Quick start and overview
  - `monitoring/docs/MONITORING_SETUP.md` - Comprehensive setup guide
  - Fixed all broken references and links across documentation
- **Improved User Experience**: Clearer paths for both simple and advanced deployments
  - Fast deployment: `docker-compose up -d` or `make run`
  - Advanced monitoring: Complete guide in monitoring directory
  - Preserved all customization options for power users

### 🎯 Repository Goals Achieved
- **Single Container Focus**: Maintained unified Docker container approach
- **Simple Deployment**: Quick start options preserved and improved
- **Advanced Customization**: All configuration options and monitoring stacks retained
- **Clean Structure**: Eliminated redundancy while preserving functionality

## [v25.0.32] - 2025-01-27

### 🎨 Beautiful Monitoring Dashboard Overhaul
- **Completely Redesigned Grafana Dashboard**: Professional, modern interface
  - 🎨 Beautiful dark theme with color-coded status indicators
  - 📊 Real-time health status with visual background colors
  - ⏱️ Container uptime tracking and system resource monitoring
  - 🌐 External IP (VPN) display with proper labeling
  - 📈 Historical trend analysis and performance metrics
  - 🎯 Individual health check status table with color coding

### 🚀 Enhanced Monitoring Server
- **Comprehensive Metrics Addition**: Extended monitoring capabilities
  - System metrics: CPU usage, memory usage, load average
  - Container metrics: Start time, uptime, external IP tracking
  - Enhanced Prometheus metrics with proper labels and help text
  - Improved error handling and logging throughout

### 📚 Documentation Excellence
- **Complete MONITORING_SETUP.md Rewrite**: Professional documentation
  - 📝 Step-by-step setup guides with clear sections and emojis
  - 🎯 Feature highlights of enhanced dashboards
  - 🔔 Alerting configuration examples and best practices
  - 🛡️ Security considerations and production deployment guides
  - 🔧 Comprehensive troubleshooting section

### 🔧 Technical Improvements
- **Enhanced Prometheus Configuration**: Better scraping strategy
- **Improved Dashboard UX**: 30-second auto-refresh, helpful descriptions
- **Mobile-Friendly Design**: Responsive dashboard that works on all devices
- **Professional Monitoring**: Production-ready monitoring stack

## [v25.0.31] - 2025-01-27

### 🚀 Docker Hub & CI/CD Improvements
- **Enhanced GitHub Actions Workflows**: Comprehensive Docker Hub tagging strategy
  - Added `stable` tag for production deployments
  - Added date-based tags (`YYYYMMDD`) for scheduled builds  
  - Added SHA-based tags (`main-<sha>`) for traceability
  - Improved OCI labels with source, documentation, and version info
- **New Release Candidate Workflow**: Build and test RC images before releases
- **Scheduled Builds**: Daily builds at 2 AM UTC for security patches
- **Tag Validation Workflow**: Validate tagging strategy without building images
- **Multi-Registry Support**: Enhanced support for Docker Hub + GitHub Container Registry

### 📚 Documentation Updates
- **Docker Hub Improvements Guide**: Comprehensive documentation of new tagging strategy
- **Updated Tag Matrix**: Clear documentation of all available tags and when they're created
- **Improved Workflow Documentation**: Better error handling and debugging information

### 🔧 Technical Enhancements
- **Better Error Handling**: Enhanced credential validation in workflows
- **Improved Conditional Logic**: Optimized builds for different trigger types
- **Enhanced Metadata**: More comprehensive OCI image labels

## [v25.0.30] - 2025-06-15

### 📖 Documentation
- **CRITICAL FIX**: Updated documentation to clarify VPN credentials file naming
  - Container expects `/config/openvpn/credentials.txt` (not `.conf`)
  - Added credentials file vs environment variable options to README.md
  - Updated .env.sample with both authentication methods
  - Fixed TROUBLESHOOTING.md examples to use correct filename
- **Security Enhancement**: Documented credentials file as recommended method over environment variables

### 🔧 Background
- Discovered inconsistency between container code (expects `credentials.txt`) and user configurations (often used `credentials.conf`)
- This caused VPN authentication failures that were difficult to diagnose
- Container will now work with either filename for backward compatibility

## [v25.0.29] - 2025-01-19

### Fixed ✅
- **Health monitoring "unknown" status** - All checks now show meaningful values
- **BusyBox compatibility** - Replaced `grep -oP` with `sed -n` for universal compatibility  
- **News server detection** - Now reads directly from NZBGet config file
- **Status file creation** - Fixed jq commands to properly parse metrics JSON array

### Technical Changes
- Line 163: `grep -oP 'inet \K[^/]+'` → `sed -n "s/.*inet \([0-9.]*\).*/\1/p"`
- Lines 303-306: Fixed status file creation to use proper jq array selectors
- News server check: Modified to read from `/config/nzbget.conf` instead of env vars
- Cross-platform: Works on x86_64, ARM64, Raspberry Pi, all Linux distributions

### Repository Cleanup
- Removed `Dockerfile.fixed` (no longer needed)
- Removed `build-fixed.sh` (fixes integrated into main code)
- Updated documentation to reflect working status
- Enhanced troubleshooting guides

### Expected Health Response
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

### Benefits
- **Out-of-the-box functionality** - Health monitoring works immediately
- **No configuration required** - Auto-detects news servers from NZBGet
- **Better observability** - Accurate status for dashboards and alerting
- **Universal compatibility** - Same functionality across all architectures 