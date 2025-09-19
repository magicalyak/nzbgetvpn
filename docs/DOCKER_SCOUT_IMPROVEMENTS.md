# Docker Scout Health Score Improvements

This document describes the improvements made to address Docker Scout health score findings.

## Improvements Implemented

### 1. Updated Base Images
- **Change**: Updated from `ghcr.io/linuxserver/nzbget:latest` to specific version `ghcr.io/linuxserver/nzbget:25.0-r9475-ls183`
- **Benefit**: Using a specific version tag ensures reproducibility and allows for proper vulnerability scanning
- **Impact**: Addresses "Outdated base images found" warning

### 2. Non-Root User Support
- **Implementation**: The LinuxServer base image already provides non-root user functionality through PUID/PGID environment variables
- **Usage**: Users can run the container as non-root by setting:
  ```bash
  docker run -e PUID=1000 -e PGID=1000 magicalyak/nzbgetvpn
  ```
- **Impact**: Addresses "No default non-root user found" warning while maintaining backward compatibility

### 3. Supply Chain Attestations
- **Added Build Metadata**: Dockerfile now includes build arguments for tracking:
  - `BUILD_DATE`: Timestamp of the build
  - `VCS_REF`: Git commit SHA
  - `VERSION`: Version tag
- **GitHub Actions Updates**: Build workflow now generates:
  - SBOM (Software Bill of Materials) via `sbom: true`
  - Build provenance via `provenance: true`
- **Impact**: Addresses "Missing supply chain attestation(s)" warning

## How to Verify Improvements

After building with these changes, Docker Scout should show:
- ✅ No high-profile vulnerabilities
- ✅ No fixable critical or high vulnerabilities
- ✅ No unapproved base images
- ✅ Supply chain attestations present
- ✅ Base images up to date
- ✅ Non-root user support available

## Running as Non-Root

To run the container as a non-root user:

```bash
# Using docker run
docker run -d \
  -e PUID=1000 \
  -e PGID=1000 \
  -e VPN_CLIENT=openvpn \
  -v /path/to/config:/config \
  magicalyak/nzbgetvpn

# Using docker-compose
services:
  nzbgetvpn:
    image: magicalyak/nzbgetvpn
    environment:
      - PUID=1000
      - PGID=1000
      - VPN_CLIENT=openvpn
```

## Building with Attestations

The GitHub Actions workflow automatically builds with attestations. To build locally with attestations:

```bash
# Build with buildx for attestation support
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --provenance=true \
  --sbom=true \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  --build-arg VCS_REF=$(git rev-parse HEAD) \
  --build-arg VERSION=$(git describe --tags --always) \
  -t magicalyak/nzbgetvpn .
```

## Security Best Practices

1. **Always run with specific user IDs**: Use PUID/PGID to avoid running as root
2. **Keep base images updated**: Regularly rebuild to get security patches
3. **Monitor vulnerabilities**: Use Docker Scout or similar tools to scan images
4. **Use specific version tags**: Avoid `:latest` tag in production deployments