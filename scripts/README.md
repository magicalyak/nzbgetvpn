# 🛠️ Build Scripts

This directory contains utility scripts for building and testing nzbgetvpn across multiple architectures.

## 🏗️ Multi-Architecture Build Script

**`build-multiarch.sh`** - Comprehensive script for building and testing multi-architecture Docker images.

### Quick Start

```bash
# Build for all supported platforms (AMD64 + ARM64)
./scripts/build-multiarch.sh

# Build ARM64 only (e.g., for Raspberry Pi testing)
./scripts/build-multiarch.sh --platforms linux/arm64

# Build and push to registry
./scripts/build-multiarch.sh --push

# Build with custom name and tag
./scripts/build-multiarch.sh --name my-nzbgetvpn --tag v1.0
```

### Features

- ✅ **Multi-platform support**: AMD64 and ARM64
- 🧪 **Automated testing**: Validates functionality on each architecture
- 🔍 **Prerequisites checking**: Verifies Docker and buildx availability
- 📊 **Performance information**: Shows expected performance by platform
- 🧹 **Cleanup options**: Optional cleanup of build environments
- 📈 **Progress reporting**: Detailed build progress and status

### Usage Examples

```bash
# Development build (local only)
./scripts/build-multiarch.sh --name nzbgetvpn-dev --tag test

# Production build (with registry push)
./scripts/build-multiarch.sh --push --name magicalyak/nzbgetvpn --tag latest

# ARM64 only for Raspberry Pi testing
./scripts/build-multiarch.sh --platforms linux/arm64 --no-test

# Verbose output for debugging
./scripts/build-multiarch.sh --verbose

# Build with cleanup
./scripts/build-multiarch.sh --cleanup
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--name IMAGE_NAME` | Docker image name | `nzbgetvpn` |
| `--tag TAG` | Docker image tag | `local-test` |
| `--platforms PLATFORMS` | Target platforms (comma-separated) | `linux/amd64,linux/arm64` |
| `--push` | Push images to registry | `false` |
| `--no-test` | Skip testing after build | Test enabled |
| `--cleanup` | Remove builder after completion | No cleanup |
| `--verbose` | Enable verbose output | Normal output |

### Environment Variables

You can also control the script behavior using environment variables:

```bash
export IMAGE_NAME="my-nzbgetvpn"
export TAG="v1.0"
export PLATFORMS="linux/arm64"
export PUSH="true"
export TEST="false"

./scripts/build-multiarch.sh
```

### Prerequisites

The script will automatically check for:
- Docker Engine
- Docker Buildx plugin
- Proper project structure (Dockerfile presence)
- Available platforms in buildx

### Testing

The script performs comprehensive testing on each built platform:

1. **Basic functionality test**: Verifies core tools (Python, OpenVPN, WireGuard)
2. **Platform detection test**: Validates architecture detection
3. **Monitoring server test**: Quick validation of HTTP monitoring endpoints

### Performance Information

The script displays expected performance characteristics for each platform:

- **AMD64**: High performance, suitable for server workloads
- **ARM64**: Power efficient, excellent for embedded devices and cloud
- **Apple Silicon**: Outstanding ARM64 performance with native Docker
- **Raspberry Pi**: Good performance with proper thermal management

## 🚀 Getting Started

1. **Clone the repository:**
   ```bash
   git clone https://github.com/magicalyak/nzbgetvpn.git
   cd nzbgetvpn
   ```

2. **Run the build script:**
   ```bash
   ./scripts/build-multiarch.sh
   ```

3. **Test the built image:**
   ```bash
   # Test ARM64 image
   docker run --rm --platform linux/arm64 nzbgetvpn:local-test /root/platform-info.sh
   
   # Test AMD64 image
   docker run --rm --platform linux/amd64 nzbgetvpn:local-test /root/platform-info.sh
   ```

## 📚 Additional Resources

- **[MULTI-ARCH.md](../MULTI-ARCH.md)**: Comprehensive multi-architecture documentation
- **[README.md](../README.md)**: Main project documentation
- **[TROUBLESHOOTING.md](../TROUBLESHOOTING.md)**: Troubleshooting guide with multi-arch section

## 🐛 Troubleshooting

### Common Issues

**Build fails with "no space left on device":**
```bash
# Clean up Docker
docker system prune -a
docker buildx prune
```

**QEMU emulation is slow:**
```bash
# This is expected for cross-platform builds
# Use native hardware for optimal performance
```

**Builder creation fails:**
```bash
# Remove existing builder and retry
docker buildx rm nzbgetvpn-builder
./scripts/build-multiarch.sh
```

### Getting Help

For build-related issues:
1. Run with `--verbose` flag for detailed output
2. Check Docker and buildx versions
3. Verify available disk space
4. Report issues on [GitHub](https://github.com/magicalyak/nzbgetvpn/issues)

---

**🎯 Ready to build? Start with `./scripts/build-multiarch.sh` and see your containers running across multiple architectures!** 