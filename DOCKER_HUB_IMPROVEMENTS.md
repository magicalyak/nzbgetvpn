# Docker Hub Tagging Strategy Improvements

## 📋 Overview

This document outlines the improvements made to ensure GitHub Actions properly create Docker Hub images with correct and comprehensive tagging strategies.

## 🎯 Current Tag Strategy

### Main Branch (`main`) Tags
When code is pushed to the main branch:
- `latest` - Always points to the latest main branch build
- `stable` - Alias for latest stable version 
- `main-<sha>` - SHA-based tag for traceability
- `YYYYMMDD` - Date-based tags for scheduled builds

### Release Tags (`v*`)
When a version tag is pushed (e.g., `v25.0.31`):
- `v25.0.31` - Full semantic version
- `v25.0` - Major.minor version
- `v25` - Major version only
- `latest` - Updated to point to latest release
- `stable` - Updated to point to latest stable release

### Release Candidate Tags
For `release/*` and `hotfix/*` branches:
- `<branch>-rc` - Release candidate for the branch
- `v25.0.31-rc.1` - Specific RC version (manual input)
- `rc-latest` - Latest release candidate
- `rc-<branch>-<sha>` - SHA-based RC tag

### Development Branch Tags
For `develop` branch:
- `develop` - Latest develop branch build
- `develop-<sha>` - SHA-based develop tag

## 🚀 New Workflows Created

### 1. Enhanced Main Workflow (`.github/workflows/build-and-publish.yml`)
**Improvements:**
- ✅ Added scheduled builds (daily at 2 AM UTC)
- ✅ Enhanced metadata with better OCI labels
- ✅ Added `stable` tag for main branch
- ✅ Added date-based tags for scheduled builds
- ✅ Added SHA-based tags for traceability
- ✅ Improved error handling and validation

### 2. Release Candidate Workflow (`.github/workflows/release-candidate.yml`)
**Purpose:** Build and tag release candidates
**Triggers:**
- Push to `release/*` branches
- Push to `hotfix/*` branches
- Manual workflow dispatch with custom RC version

### 3. Tag Validation Workflow (`.github/workflows/validate-tagging.yml`)
**Purpose:** Validate tagging strategy without building images
**Triggers:**
- Manual workflow dispatch
- PR changes to Docker workflows or Dockerfile

## 🏷️ Complete Tag Matrix

| Trigger | Branch/Tag | Generated Tags |
|---------|------------|----------------|
| Push | `main` | `latest`, `stable`, `main-<sha>` |
| Push | `develop` | `develop`, `develop-<sha>` |
| Push | `v25.0.31` | `v25.0.31`, `v25.0`, `v25`, `latest`, `stable` |
| Push | `release/v25.0.31` | `release-v25.0.31-rc`, `rc-latest`, `rc-release-v25.0.31-<sha>` |
| Schedule | `main` (daily) | `latest`, `stable`, `main-<sha>`, `20240101` |
| Manual | Any (RC) | Custom RC version (e.g., `v25.0.31-rc.1`) |

## 🔧 Technical Improvements

### Multi-Architecture Support
- ✅ Builds for `linux/amd64` and `linux/arm64`
- ✅ Uses Docker Buildx with manifest lists
- ✅ Platform-specific caching strategies
- ✅ Architecture-specific testing

### Security & Quality
- ✅ Trivy vulnerability scanning
- ✅ SARIF upload to GitHub Security tab
- ✅ Multi-platform testing before release
- ✅ Comprehensive healthchecks

### Registry Support
- ✅ Docker Hub (`docker.io/magicalyak/nzbgetvpn`)
- ✅ GitHub Container Registry (`ghcr.io/magicalyak/nzbgetvpn`)
- ✅ Automatic README updates on Docker Hub

## 📊 Workflow Validation

Run the validation workflow to test tagging strategies:

```bash
# Via GitHub UI: Actions -> Validate Docker Hub Tagging -> Run workflow
# Or via CLI:
gh workflow run validate-tagging.yml
```

## 🎉 Expected Results

### Docker Hub Repository: `magicalyak/nzbgetvpn`

**Current Production Tags:**
- `latest` - Latest stable release
- `stable` - Same as latest
- `v25.0.30` - Current latest version tag
- `v25.0` - Latest v25.0.x release
- `v25` - Latest v25.x.x release

**After Next Release (v25.0.31):**
- `latest` - Points to v25.0.31
- `stable` - Points to v25.0.31
- `v25.0.31` - Specific version
- `v25.0` - Points to v25.0.31
- `v25` - Points to v25.0.31

**Development/RC Tags:**
- `develop` - Latest develop branch
- `rc-latest` - Latest release candidate
- `v25.0.31-rc.1` - Specific release candidate

## 🛠️ Usage Examples

### Production Deployment
```yaml
# docker-compose.yml
services:
  nzbgetvpn:
    image: magicalyak/nzbgetvpn:latest    # Always latest stable
    # OR
    image: magicalyak/nzbgetvpn:stable    # Explicit stable tag  
    # OR
    image: magicalyak/nzbgetvpn:v25.0     # Pin to major.minor
```

### Testing/Development
```yaml
services:
  nzbgetvpn:
    image: magicalyak/nzbgetvpn:develop         # Latest development
    # OR
    image: magicalyak/nzbgetvpn:rc-latest       # Latest release candidate
    # OR  
    image: magicalyak/nzbgetvpn:v25.0.31-rc.1   # Specific RC version
```

## 🔍 Monitoring & Troubleshooting

### Check Current Tags
```bash
# List all tags
curl -s "https://hub.docker.com/v2/repositories/magicalyak/nzbgetvpn/tags/" | jq -r '.results[].name'

# Check specific tag
docker manifest inspect magicalyak/nzbgetvpn:latest
```

### Workflow Logs
- **Build logs:** Actions tab in GitHub repository
- **Tag validation:** Run validate-tagging workflow
- **Security scans:** Security tab in GitHub repository

## 📝 Next Steps

1. **Test the workflows** by creating a test release
2. **Monitor the first scheduled build** (runs daily at 2 AM UTC)  
3. **Validate RC workflow** by creating a `release/v25.0.31` branch
4. **Update documentation** to reference new tag patterns
5. **Configure branch protection** for `release/*` branches

## 🤝 Contributing

When creating releases:
1. Use semantic versioning (e.g., `v25.0.31`)
2. Test with RC workflow first (`release/v25.0.31` branch)
3. Validate tags using the validation workflow
4. Monitor build logs for any issues

---

*Last updated: January 2025*
*Workflow version: Enhanced with comprehensive tagging strategy* 