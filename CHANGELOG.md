# Changelog

All notable changes to nzbgetvpn will be documented in this file.

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