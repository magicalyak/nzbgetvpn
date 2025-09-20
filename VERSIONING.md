# Versioning Strategy

## Overview

This project follows the upstream NZBGet version numbering with additional patch versioning for container-specific updates.

## Version Format

```
v<NZBGET_MAJOR>.<NZBGET_MINOR>.<CONTAINER_PATCH>
```

- **NZBGET_MAJOR**: Major version from upstream NZBGet (currently 25)
- **NZBGET_MINOR**: Minor version from upstream NZBGet (currently 0)
- **CONTAINER_PATCH**: Our container-specific patch number

Example: `v25.0.43` means NZBGet v25.0 with our 43rd container update

## Build and Release Strategy

### Primary Build Method: GitHub Actions

We use GitHub Actions as the primary build pipeline for consistency and control:

1. **Tagged Releases** (`v*` tags)
   - Triggers multi-architecture builds (amd64, arm64)
   - Pushes to both Docker Hub and GitHub Container Registry
   - Creates immutable version tags
   - Updates `latest` and `stable` tags

2. **Manual Dispatch**
   - Available for testing via workflow_dispatch
   - Can build without pushing to registries

### Docker Hub Configuration

Docker Hub should be configured as follows:

1. **Disable Autobuild** on Docker Hub side to avoid conflicts
2. Let GitHub Actions handle all builds and pushes
3. Use Docker Hub only as a registry, not a build platform

### Release Process

1. **Check upstream NZBGet version**
   ```bash
   # Check current NZBGet version in Dockerfile
   grep "NZBGET_VERSION" Dockerfile
   ```

2. **Create release tag**
   ```bash
   # For container updates (no NZBGet version change)
   git tag v25.0.44
   git push origin v25.0.44

   # For NZBGet version updates
   git tag v26.0.1  # When NZBGet updates to v26
   git push origin v26.0.1
   ```

3. **GitHub Actions automatically**
   - Builds multi-architecture images
   - Pushes to Docker Hub with tags:
     - `magicalyak/nzbgetvpn:v25.0.44`
     - `magicalyak/nzbgetvpn:25.0.44`
     - `magicalyak/nzbgetvpn:25.0`
     - `magicalyak/nzbgetvpn:25`
     - `magicalyak/nzbgetvpn:latest`
     - `magicalyak/nzbgetvpn:stable`
   - Pushes to GitHub Container Registry with same tags
   - Runs security scanning with Trivy

## Version Tags Explained

| Tag | Description | Example |
|-----|-------------|---------|
| `latest` | Most recent stable release | Points to newest version |
| `stable` | Same as latest, for clarity | Points to newest version |
| `v25.0.43` | Specific version | Immutable, never changes |
| `25.0.43` | Version without 'v' prefix | Same as above |
| `25.0` | Minor version tracking | Points to latest patch |
| `25` | Major version tracking | Points to latest minor |

## Development Versions

Development/test versions should use suffixes:
- `v25.0.44-beta` - Beta release
- `v25.0.44-rc1` - Release candidate
- `v25.0.44-test` - Test build

## Deprecation Policy

- Version tags are never deleted
- Old major versions supported for 6 months after new major release
- Security patches backported to previous major version for critical issues

## Security Updates

When security vulnerabilities are found:
1. Increment patch version immediately
2. Document the fix in CHANGELOG.md
3. Create GitHub Security Advisory if critical

## Monitoring Versions

Check current versions:
```bash
# Docker Hub
docker pull magicalyak/nzbgetvpn:latest
docker inspect magicalyak/nzbgetvpn:latest | grep -i version

# GitHub Container Registry
docker pull ghcr.io/magicalyak/nzbgetvpn:latest
docker inspect ghcr.io/magicalyak/nzbgetvpn:latest | grep -i version
```

## Best Practices

1. **Always test locally** before creating release tag
2. **Update CHANGELOG.md** with every version bump
3. **Use semantic commit messages** for automatic changelog generation
4. **Monitor upstream NZBGet** for version updates
5. **Run security scans** before releasing