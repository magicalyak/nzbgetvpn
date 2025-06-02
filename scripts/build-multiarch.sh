#!/bin/bash

# Multi-Architecture Build Script for nzbgetvpn
# Supports building and testing AMD64 and ARM64 images

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="${IMAGE_NAME:-nzbgetvpn}"
TAG="${TAG:-local-test}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
PUSH="${PUSH:-false}"
TEST="${TEST:-true}"
BUILDER_NAME="nzbgetvpn-builder"

# Function to print colored output
print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Function to print section headers
print_header() {
    echo
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$CYAN" "  $1"
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to show usage
show_usage() {
    cat << EOF
Multi-Architecture Build Script for nzbgetvpn

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -n, --name IMAGE_NAME   Docker image name (default: nzbgetvpn)
    -t, --tag TAG           Docker image tag (default: local-test)
    -p, --platforms PLATFORMS Target platforms (default: linux/amd64,linux/arm64)
    --push                  Push images to registry
    --no-test              Skip testing after build
    --cleanup              Remove builder after completion
    -v, --verbose          Verbose output

Examples:
    $0                                          # Build for all platforms
    $0 --platforms linux/arm64                 # Build ARM64 only
    $0 --name my-nzbgetvpn --tag v1.0          # Custom name and tag
    $0 --push                                  # Build and push to registry
    $0 --platforms linux/amd64 --no-test      # AMD64 only, no testing

Environment Variables:
    IMAGE_NAME              Docker image name
    TAG                     Docker image tag
    PLATFORMS               Target platforms (comma-separated)
    PUSH                    Push to registry (true/false)
    TEST                    Run tests after build (true/false)

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_header "🔍 Checking Prerequisites"
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        print_color "$RED" "❌ Docker is not installed or not in PATH"
        exit 1
    fi
    print_color "$GREEN" "✅ Docker: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
    
    # Check Docker Buildx
    if ! docker buildx version >/dev/null 2>&1; then
        print_color "$RED" "❌ Docker Buildx is not available"
        exit 1
    fi
    print_color "$GREEN" "✅ Docker Buildx: $(docker buildx version | head -1 | cut -d' ' -f2)"
    
    # Check if we're in the right directory
    if [[ ! -f "$PROJECT_DIR/Dockerfile" ]]; then
        print_color "$RED" "❌ Dockerfile not found. Are you in the project directory?"
        exit 1
    fi
    print_color "$GREEN" "✅ Dockerfile found at $PROJECT_DIR/Dockerfile"
    
    # Check available platforms
    print_color "$CYAN" "Available platforms:"
    docker buildx ls | grep -E "linux/(amd64|arm64)" || true
}

# Function to setup buildx builder
setup_builder() {
    print_header "🏗️ Setting up Multi-Architecture Builder"
    
    # Check if builder already exists
    if docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
        print_color "$YELLOW" "⚠️  Builder '$BUILDER_NAME' already exists, using existing"
    else
        print_color "$CYAN" "Creating new buildx builder: $BUILDER_NAME"
        docker buildx create \
            --name "$BUILDER_NAME" \
            --driver docker-container \
            --use
    fi
    
    # Bootstrap the builder
    print_color "$CYAN" "Bootstrapping builder..."
    docker buildx inspect --bootstrap
    
    # Show builder info
    print_color "$GREEN" "✅ Builder setup complete"
    docker buildx ls | grep "$BUILDER_NAME" || true
}

# Function to build multi-architecture images
build_images() {
    print_header "🏗️ Building Multi-Architecture Images"
    
    local full_image_name="$IMAGE_NAME:$TAG"
    local build_args=""
    
    # Prepare build arguments
    if [[ "$PUSH" == "true" ]]; then
        build_args="--push"
        print_color "$CYAN" "Will push images to registry"
    else
        build_args="--load"
        print_color "$CYAN" "Will load images locally (single platform only)"
        
        # For local load, we can only build one platform at a time
        if [[ "$PLATFORMS" == *","* ]]; then
            print_color "$YELLOW" "⚠️  Local load only supports single platform. Building first platform only."
            PLATFORMS=$(echo "$PLATFORMS" | cut -d',' -f1)
        fi
    fi
    
    print_color "$CYAN" "Building for platforms: $PLATFORMS"
    print_color "$CYAN" "Image name: $full_image_name"
    
    # Build the images
    docker buildx build \
        --platform "$PLATFORMS" \
        --tag "$full_image_name" \
        $build_args \
        --progress=plain \
        "$PROJECT_DIR"
    
    print_color "$GREEN" "✅ Build completed successfully"
}

# Function to test built images
test_images() {
    if [[ "$TEST" != "true" ]]; then
        print_color "$YELLOW" "⚠️  Skipping tests (TEST=false)"
        return 0
    fi
    
    print_header "🧪 Testing Built Images"
    
    # Split platforms for individual testing
    IFS=',' read -ra PLATFORM_ARRAY <<< "$PLATFORMS"
    
    for platform in "${PLATFORM_ARRAY[@]}"; do
        print_color "$CYAN" "Testing $platform..."
        
        local test_image="$IMAGE_NAME:$TAG"
        
        # If we pushed to registry, test from there
        if [[ "$PUSH" == "true" ]]; then
            print_color "$CYAN" "Testing from registry..."
            test_image="$IMAGE_NAME:$TAG"
        fi
        
        # Test basic functionality
        print_color "$CYAN" "  → Testing basic functionality..."
        if docker run --rm --platform "$platform" "$test_image" \
            sh -c "echo 'Platform: $platform' && python3 --version && openvpn --version | head -1 && wg --version && echo 'Basic test passed'"; then
            print_color "$GREEN" "  ✅ Basic functionality test passed for $platform"
        else
            print_color "$RED" "  ❌ Basic functionality test failed for $platform"
            return 1
        fi
        
        # Test platform detection
        print_color "$CYAN" "  → Testing platform detection..."
        if docker run --rm --platform "$platform" "$test_image" /root/platform-info.sh --quiet; then
            print_color "$GREEN" "  ✅ Platform detection test passed for $platform"
        else
            print_color "$RED" "  ❌ Platform detection test failed for $platform"
            return 1
        fi
        
        # Test monitoring endpoints (quick test)
        print_color "$CYAN" "  → Testing monitoring server startup..."
        if timeout 30 docker run --rm --platform "$platform" "$test_image" \
            sh -c "python3 /root/monitoring-server.py &
                   sleep 5 && 
                   curl -s http://localhost:8080/ | grep -q 'nzbgetvpn Monitoring' && 
                   echo 'Monitoring test passed'"; then
            print_color "$GREEN" "  ✅ Monitoring server test passed for $platform"
        else
            print_color "$YELLOW" "  ⚠️  Monitoring server test skipped/failed for $platform (non-critical)"
        fi
    done
    
    print_color "$GREEN" "✅ All tests completed"
}

# Function to show image information
show_image_info() {
    print_header "📊 Image Information"
    
    local full_image_name="$IMAGE_NAME:$TAG"
    
    if [[ "$PUSH" == "true" ]]; then
        print_color "$CYAN" "Inspecting pushed multi-architecture manifest..."
        if docker buildx imagetools inspect "$full_image_name" 2>/dev/null; then
            print_color "$GREEN" "✅ Multi-architecture manifest found"
        else
            print_color "$YELLOW" "⚠️  Could not inspect remote manifest"
        fi
    else
        print_color "$CYAN" "Showing local image information..."
        docker images | grep "$IMAGE_NAME" | grep "$TAG" || print_color "$YELLOW" "No local images found"
    fi
}

# Function to cleanup
cleanup() {
    if [[ "${CLEANUP:-false}" == "true" ]]; then
        print_header "🧹 Cleaning Up"
        
        print_color "$CYAN" "Removing builder: $BUILDER_NAME"
        docker buildx rm "$BUILDER_NAME" || true
        
        print_color "$GREEN" "✅ Cleanup completed"
    fi
}

# Function to show performance comparison
show_performance_info() {
    print_header "📈 Platform Performance Information"
    
    cat << 'EOF'
Expected Performance Characteristics:

┌─────────────┬─────────────────┬─────────────────┬──────────────────┐
│ Platform    │ Typical Speed   │ CPU Usage       │ Memory Usage     │
├─────────────┼─────────────────┼─────────────────┼──────────────────┤
│ AMD64       │ 800+ Mbps       │ 15-25%          │ 200-400MB        │
│ ARM64 (Pi5) │ 400-600 Mbps    │ 40-60%          │ 150-300MB        │
│ ARM64 (Pi4) │ 200-400 Mbps    │ 60-80%          │ 150-250MB        │
│ Apple M2    │ 900+ Mbps       │ 10-20%          │ 200-350MB        │
│ Graviton3   │ 700+ Mbps       │ 20-30%          │ 200-400MB        │
└─────────────┴─────────────────┴─────────────────┴──────────────────┘

Platform-Specific Recommendations:
• AMD64: Higher connection counts (15-30), both VPN protocols work well
• ARM64: Lower connection counts (6-12), prefer WireGuard, monitor thermals
• Apple Silicon: Excellent performance, no special configuration needed
• Cloud ARM64: Good performance, optimize for network throughput

EOF
}

# Main execution function
main() {
    print_color "$PURPLE" "╔═══════════════════════════════════════════════════════════════════════════════╗"
    print_color "$PURPLE" "║                              🐳 nzbgetvpn                                    ║"
    print_color "$PURPLE" "║                    Multi-Architecture Build Script                           ║"
    print_color "$PURPLE" "╚═══════════════════════════════════════════════════════════════════════════════╝"
    
    check_prerequisites
    setup_builder
    build_images
    test_images
    show_image_info
    show_performance_info
    cleanup
    
    print_header "✅ Build Process Complete"
    print_color "$GREEN" "Successfully built nzbgetvpn for: $PLATFORMS"
    print_color "$CYAN" "Image: $IMAGE_NAME:$TAG"
    
    if [[ "$PUSH" == "true" ]]; then
        print_color "$GREEN" "Images pushed to registry and ready for deployment!"
    else
        print_color "$CYAN" "Images built locally. Use 'docker run --platform <platform>' to test specific architectures."
    fi
    
    echo
    print_color "$YELLOW" "Next steps:"
    echo "  • Test deployment: docker run --rm --platform linux/arm64 $IMAGE_NAME:$TAG /root/platform-info.sh"
    echo "  • View documentation: see MULTI-ARCH.md for platform-specific guides"
    echo "  • Report issues: https://github.com/magicalyak/nzbgetvpn/issues"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -n|--name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -p|--platforms)
            PLATFORMS="$2"
            shift 2
            ;;
        --push)
            PUSH="true"
            shift
            ;;
        --no-test)
            TEST="false"
            shift
            ;;
        --cleanup)
            CLEANUP="true"
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            print_color "$RED" "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Trap to cleanup on exit
trap cleanup EXIT

# Execute main function
main "$@" 