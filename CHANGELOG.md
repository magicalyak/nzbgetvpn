# Changelog

All notable changes to nzbgetvpn will be documented in this file.

## [v25.3.4] - 2025-09-20

### 🔄 Revert USER Directive Changes

#### Critical Fix
- **Removed USER directive**: Was breaking s6-overlay initialization
- **Restored v25.3.1 approach**: No USER directive, proper functionality
- **Kept security updates**: Base image and package updates retained

#### Why This Change
- LinuxServer's s6-overlay REQUIRES root to initialize
- USER directive prevents proper container startup
- PUID/PGID mechanism already provides non-root execution
- v25.3.1 had an A score without USER directive

#### Technical Details
- s6-overlay handles privilege dropping via PUID/PGID
- More flexible than fixed USER directive
- Docker Scout's "no non-root user" is a false positive for s6 containers
- Container services DO run as non-root (PUID/PGID)

#### Expected Outcome
- Container functionality restored
- Docker Scout score should return to A (as in v25.3.1)
- Full backward compatibility maintained

## [v25.3.3] - 2025-09-20

### 🔒 Docker Scout Compliance Fixes

#### Policy Compliance
- **Fixed non-root user declaration**: USER directive is now the final instruction
- **Supply chain attestation**: Enhanced build process with proper attestation
- **Removed problematic SUID/SGID stripping**: Prevents breaking system binaries
- **Proper user permissions**: Using LinuxServer's abc user (uid 911)

#### Technical Improvements
- USER abc is now the last directive in Dockerfile (Scout requirement)
- Removed back-and-forth USER switching that confused Scout
- Enhanced manifest creation with --append flag
- Maintains full s6-overlay compatibility

#### Docker Scout Score
- Fixes "No default non-root user found" violation
- Addresses supply chain attestation requirements
- Should improve from D grade to B or better

## [v25.3.2] - 2025-09-20

### 🔒 Additional Security Hardening

#### Docker Scout Compliance
- **Explicit non-root user**: Added USER directive for Docker Scout compliance
- **SUID/SGID removal**: Stripped unnecessary privilege bits from binaries
- **Package cleanup**: Removed wget and other potentially vulnerable packages
- **Temporary file cleanup**: Enhanced cleanup of /tmp and /var/tmp

#### Security Improvements
- Added explicit non-root user (uid/gid 1000) while maintaining s6-overlay compatibility
- Removed SUID/SGID bits from binaries that don't require elevated privileges
- Enhanced cleanup of temporary files and caches
- Removed unnecessary packages to reduce attack surface

#### Technical Details
- LinuxServer's s6-overlay still handles privilege dropping via PUID/PGID
- USER directive satisfies Docker Scout's non-root user policy
- Maintains full backward compatibility with existing deployments

## [v25.3.1] - 2025-09-20

### 🔒 Security Update & Version Alignment

#### Base Image Update
- **Updated to NZBGet v25.3**: Upgraded from v25.0 to v25.3 (LinuxServer build ls213)
- **Security patches**: Fixes 3 vulnerabilities identified by Docker Scout
- **Improved Docker Scout score**: From D to improved security rating
- **Package updates**: All Alpine packages updated to latest security patches

#### Version Alignment
- **New versioning scheme**: Now follows actual NZBGet version in base image
- **Version jump**: From v25.0.44 to v25.3.1 to match NZBGet v25.3
- **Future versioning**: Will track LinuxServer's NZBGet updates

### 🛡️ Security Improvements
- Added `apk upgrade` to update all packages for security
- Base image update includes latest CVE fixes
- Reduced attack surface with updated dependencies

## [v25.0.44] - 2025-09-20

### 🔒 Enhanced VPN Kill Switch Security
- **Strict Kill Switch Implementation**: Multi-layer protection against data leaks
  - ✅ **Default DROP Policies**: All iptables chains (INPUT, FORWARD, OUTPUT) set to DROP
  - ✅ **DNS Leak Prevention**: Blocks all DNS queries on eth0, only allows through VPN
  - ✅ **Active VPN Monitoring**: Service that stops NZBGet if VPN connection fails
  - ✅ **Automatic Recovery**: NZBGet restarts when VPN connection is restored
  - ✅ **Configurable Health Checks**: VPN_CHECK_INTERVAL and VPN_MAX_FAILURES options

### 🛡️ Security Improvements
- **Multi-Layer Protection**: Comprehensive kill switch with multiple fail-safes
  - Strict firewall rules with default deny policies
  - Packet logging for blocked traffic (when DEBUG=true)
  - Automatic service shutdown on VPN failure
  - DNS leak prevention on all interfaces
  - VPN connection monitoring every 30 seconds (configurable)

### 📚 Documentation Updates
- **New Documentation**: Comprehensive guides for security and versioning
  - Added VERSIONING.md for version strategy
  - Added DOCKER_BUILD_SETUP.md for build configuration
  - Added VPN_KILLSWITCH_SECURITY.md for security features
  - Added kill switch verification tools and test scripts
  - Reorganized documentation structure

### 🔧 Infrastructure Improvements
- **Docker Hub Configuration**: Streamlined build and deployment
  - Disabled Docker Hub Autobuild (GitHub Actions handles all builds)
  - Added Docker Scout configuration for vulnerability scanning
  - Configured immutable version tags for security
  - Removed duplicate scheduled build workflow

### 🐛 Fixes
- Fixed Docker Scout health score warnings
- Fixed GitHub Actions workflow permissions for security scanning
- Resolved potential security vulnerabilities in base image

## [v25.0.39] - 2025-01-27

### 🚀 GitHub Actions Workflow Rate Limiting Fixes
- **Fixed GHCR Rate Limiting Issues**: Comprehensive fixes for workflow failures
  - ✅ **Retry Logic with Exponential Backoff**: Added robust retry mechanism for GHCR pushes (up to 5 attempts)
  - ✅ **Rate Limit Monitoring**: Pre-push rate limit checking using GitHub API
  - ✅ **Graceful Degradation**: Workflow continues if GHCR fails but Docker Hub succeeds
  - ✅ **Enhanced Error Handling**: Improved error reporting and workflow resilience
  - ✅ **Registry Operation Delays**: Added strategic delays between registry operations

### 🔧 Workflow Reliability Improvements
- **Separate Scheduled Builds**: Created `scheduled-build.yml` for routine builds
  - Docker Hub only pushes to avoid GHCR rate limits on automated builds
  - GHCR reserved for tagged releases only
  - Nightly builds with `nightly-YYYYMMDD` tags
  - Reduced registry load with targeted build strategy
- **Enhanced Image Inspection**: Improved image verification with conditional GHCR checks
- **Better Error Recovery**: Workflows no longer fail completely due to GHCR rate limiting

### 🎯 Production Deployment Strategy
- **Primary Registry Focus**: Docker Hub as primary registry with GHCR as secondary
- **Rate Limit Mitigation**: Strategic delays and retry logic prevent 429 errors
- **Workflow Resilience**: Builds continue even if secondary registry fails
- **Enhanced Monitoring**: Better visibility into rate limiting and registry status

## [v25.0.38] - 2025-06-15

### 🏠 Home Assistant Integration
- **Complete Home Assistant Integration**: Production-ready monitoring dashboard
  - ✅ **REST Sensors**: Comprehensive sensor configuration for health and status endpoints
  - ✅ **Template Sensors**: Individual health checks and system metrics extraction
  - ✅ **Binary Sensors**: True/false states for easy automation and alerting
  - ✅ **Smart Notifications**: Automated alerts for health issues, VPN disconnections, IP leaks
  - ✅ **Two Dashboard Options**: Simple (built-in cards) and Advanced (custom components)
  - ✅ **Comprehensive Documentation**: Complete setup guide with troubleshooting

### 🚀 Production Deployment Success
- **Live Deployment Verification**: Successfully deployed and tested on rocky.gamull.com
  - ✅ **Fixed psutil Dependencies**: Resolved Python module issues in production
  - ✅ **Systemd Service Integration**: Proper integration with existing systemd service
  - ✅ **All Endpoints Operational**: Health, status, metrics, and NZBGet web interface
  - ✅ **Enhanced Monitoring Active**: All health checks operational and reporting

### 📊 Real-Time Monitoring Features
- **Professional Dashboard Components**: Beautiful, functional Home Assistant cards
  - 🎨 **Color-Coded Status Indicators**: Visual health status with state-based coloring
  - 📈 **Historical Graphs**: Health status trends over time
  - 🔄 **Quick Action Buttons**: Direct access to metrics, NZBGet, and refresh functions
  - 📱 **Mobile-Friendly Design**: Responsive layout for all devices
  - ⚡ **Real-Time Updates**: 30-second health polling, 60-second status updates

### 🔔 Intelligent Alerting System
- **Smart Notification Logic**: Configurable alerts with false-positive prevention
  - 🚨 **Health Alerts**: Container unhealthy state notifications (2-minute delay)
  - 🔌 **VPN Disconnection Alerts**: Immediate VPN interface down notifications
  - 🛡️ **IP Leak Detection**: Critical priority alerts for external IP changes
  - 📧 **Multiple Notification Services**: Discord, Telegram, Mobile App support

### 🌐 Live Production Endpoints
- **Verified Working Endpoints**: All services operational on rocky.gamull.com
  - **Health**: `http://rocky.gamull.com:8081/health` - Comprehensive health status
  - **Status**: `http://rocky.gamull.com:8081/status` - Detailed system information  
  - **Metrics**: `http://rocky.gamull.com:8081/metrics` - Performance metrics
  - **NZBGet**: `http://rocky.gamull.com:6790` - NZBGet web interface

### 📚 Enhanced Documentation
- **Complete Home Assistant Guide**: Professional documentation with examples
  - 🚀 **Quick Setup Guide**: Step-by-step configuration instructions
  - 📊 **Sensor Reference**: Complete table of all available sensors and their values
  - 🎨 **Dashboard Examples**: Multiple Lovelace card configurations
  - 🔧 **Troubleshooting Section**: Common issues and solutions
  - 🔗 **Integration Examples**: Discord, Telegram, Mobile App notifications

## [v25.0.37] - 2025-01-27

### 🔍 Comprehensive Health Check System
- **Enhanced Health Monitoring**: Complete overhaul based on transmissionvpn approach
  - ✅ **Configurable IP leak detection** with external IP monitoring and change tracking
  - ✅ **DNS leak detection** with DNS server change monitoring and alerts
  - ✅ **VPN connectivity testing** with actual network validation through VPN tunnel
  - ✅ **News server connectivity** validation for Usenet server access
  - ✅ **Enhanced NZBGet monitoring** with JSON-RPC API validation
  - ✅ **System resource monitoring** with CPU, memory, disk, and network metrics

### ⚙️ Advanced Health Check Configuration
- **Environment Variable Control**: Complete customization of all health checks
  - `CHECK_DNS_LEAK=true/false` - Monitor DNS server changes
  - `CHECK_IP_LEAK=true/false` - Monitor external IP changes  
  - `CHECK_VPN_CONNECTIVITY=true/false` - Test VPN tunnel connectivity
  - `CHECK_NEWS_SERVER=true/false` - Test Usenet server access
  - `HEALTH_CHECK_HOST=google.com` - Configurable connectivity test host
  - `HEALTH_CHECK_TIMEOUT=10` - Configurable timeout for operations
  - `EXTERNAL_IP_SERVICE=ifconfig.me` - Configurable IP detection service
  - `METRICS_ENABLED=true/false` - Enable detailed metrics collection

### 📊 Enhanced Health Status System
- **Multiple Health Status Levels**: Intelligent health classification
  - **healthy** (green) - All checks passed
  - **warning** (yellow) - Non-critical issues (news server, IP changes)
  - **degraded** (orange) - Important issues (DNS, VPN connectivity)
  - **unhealthy** (red) - Critical issues (NZBGet down, VPN interface down)
- **Detailed Exit Codes**: Specific exit codes for different failure scenarios (0-8)
- **Comprehensive Status File**: JSON status with configuration and check details

### 🛡️ Security & Leak Detection
- **IP Leak Monitoring**: Track external IP changes to detect VPN disconnections
- **DNS Leak Detection**: Monitor DNS server changes to prevent DNS leaks
- **VPN Tunnel Validation**: Active network testing through VPN interface
- **Historical Tracking**: Store previous IPs and DNS servers for comparison

### 📖 Comprehensive Documentation
- **New HEALTHCHECK_OPTIONS.md**: Complete configuration guide with examples
  - Quick setup examples for different use cases
  - Detailed configuration tables and options
  - Health status level explanations
  - Testing and troubleshooting guides
  - Security considerations and best practices
- **Enhanced README.md**: New health check section with configuration examples
- **Updated Monitoring Documentation**: Integration of health check features

### 🔧 Technical Improvements
- **Smart VPN Interface Detection**: Auto-detection of tun0/wg0 interfaces
- **Improved Error Handling**: Better logging and error recovery throughout
- **Enhanced Metrics Collection**: Response times, success rates, and system metrics
- **Fixed Logging Issues**: Prevented debug output from interfering with function returns
- **Multiple IP Service Fallbacks**: Redundant external IP detection services
- **Enhanced Timeout Handling**: Configurable timeouts for all network operations

## [v25.0.36] - 2025-01-27

### 🧹 Clean Docker Hub Release Strategy
- **Simplified Tagging Strategy**: Complete overhaul of Docker Hub tagging for clean releases
  - ✅ **Only Version Tags**: Removed all branch-based tags (main, main-xxxx) from Docker Hub
  - ✅ **Release-Only Builds**: Only trigger builds on version tag pushes (v*)
  - ✅ **Clean Tag Set**: v25.0.36, 25.0.36, v25.0, 25.0, v25, 25, latest, stable
  - ❌ **No Development Tags**: No more clutter with SHA-based or branch tags
  - 🎯 **Predictable Releases**: Users get consistent, clean version tags

### 🔧 GitHub Actions Workflow Improvements
- **Fixed "Invalid Reference Format" Errors**: Comprehensive workflow debugging and fixes
  - Enhanced conditional expressions in docker/metadata-action tags
  - Added explicit event_name checks for all tag types
  - Comprehensive tag validation to catch invalid references early
  - Safety checks for JSON parsing in manifest creation steps
  - Improved error handling and debugging output for troubleshooting

### 🚀 Workflow Optimization
- **Streamlined Build Process**: Simplified workflow for better reliability
  - Removed unnecessary credential validation steps
  - Eliminated complex conditional logic that caused issues
  - Focused workflow on release builds only
  - Removed scheduled builds and PR builds for Docker Hub
  - Maintained GHCR support for development if needed

### 📋 Simple Version Tag Workflow
- **Backup Tagging System**: Added simple-version-tags.yml workflow
  - Ensures version tags are always created even if main workflow has issues
  - Waits for main build completion then creates version tags
  - Provides redundancy for critical version tag creation
  - Manual fallback for version tag generation

### 🎯 User Experience Improvements
- **Cleaner Docker Hub Repository**: Professional appearance with only release versions
- **Faster Builds**: No unnecessary builds on development commits
- **Predictable Tagging**: Clear, consistent version tag patterns
- **Better Documentation**: Updated integration guides for existing monitoring setups

### 🔗 Enhanced Monitoring Integration
- **Existing Infrastructure Support**: Comprehensive guides for integrating with existing setups
  - Step-by-step Prometheus configuration for adding nzbgetvpn metrics
  - Container discovery commands for different Docker environments
  - Grafana dashboard import process for existing instances
  - Ready-to-use alerting rules for existing Prometheus setups
  - Network connectivity troubleshooting across Docker networks

## [v25.0.34] - 2025-01-27

### 🔗 Monitoring Integration Enhancements
- **New Integration Option**: Added comprehensive guide for existing Prometheus & Grafana setups
  - 📋 Step-by-step Prometheus configuration for adding nzbgetvpn metrics
  - 🎯 Container discovery commands for different Docker environments
  - 📊 Grafana dashboard import process for existing instances
  - 🔔 Ready-to-use alerting rules for existing Prometheus alert managers

### 🛠️ Configuration Improvements
- **Fixed Prometheus Configuration**: Removed incorrect `params` section from prometheus.yml
  - Eliminated unnecessary `format: ['prometheus']` parameter
  - Streamlined scraping configuration for better reliability
  - Improved compatibility with standard Prometheus setups

### 📚 Enhanced Documentation
- **Updated README.md**: Added "Option 0" for existing infrastructure integration
  - Quick start guide for users with existing monitoring
  - Clear separation between new deployments and integrations
  - Improved user experience for different deployment scenarios
- **Comprehensive Integration Guide**: Detailed troubleshooting for common integration issues
  - Network connectivity solutions across Docker networks
  - Dashboard data troubleshooting steps
  - Container accessibility fixes for different setups

### 🎯 User Experience Improvements
- **Flexible Deployment Options**: Three clear monitoring paths
  - Option 0: Integration with existing Prometheus/Grafana (minimal overhead)
  - Option 1: Complete Prometheus stack (new deployments)
  - Option 2: Complete InfluxDB stack (alternative approach)
- **Professional Integration**: Follows monitoring best practices for multi-service environments

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