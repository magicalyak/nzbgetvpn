#!/bin/bash
set -e

# Version for this release
VERSION="v25.0.25"
IMAGE_NAME="magicalyak/nzbgetvpn"

echo "🚀 Building nzbgetvpn $VERSION with monitoring fixes..."

# Check if we're in a clean git state
if [[ -n $(git status --porcelain) ]]; then
    echo "⚠️  Warning: Working directory has uncommitted changes"
    echo "   Consider committing your changes before building a release"
fi

# Build the image with version tags
echo "📦 Building Docker image..."
docker build -f Dockerfile.fixed \
    -t "${IMAGE_NAME}:${VERSION}" \
    -t "${IMAGE_NAME}:latest-fixed" \
    -t "${IMAGE_NAME}:v25-fixed" \
    .

echo "✅ Build complete!"
echo ""
echo "🏷️  Available tags:"
echo "   - ${IMAGE_NAME}:${VERSION}"
echo "   - ${IMAGE_NAME}:latest-fixed"
echo "   - ${IMAGE_NAME}:v25-fixed"

echo ""
echo "🧪 Testing the build..."
if docker run --rm "${IMAGE_NAME}:${VERSION}" grep -n "sed -n" /root/healthcheck.sh > /dev/null; then
    echo "✅ BusyBox compatibility fix confirmed"
else
    echo "❌ BusyBox compatibility check failed"
    exit 1
fi

echo ""
echo "🚀 To release this version:"
echo "   1. Commit your changes: git add . && git commit -m 'fix: Add monitoring and BusyBox compatibility fixes'"
echo "   2. Create and push tag: git tag ${VERSION} && git push origin ${VERSION}"
echo "   3. Push images: docker push ${IMAGE_NAME}:${VERSION} && docker push ${IMAGE_NAME}:latest-fixed"
echo ""
echo "📊 To use the fixed version:"
echo "   docker-compose.yml: image: ${IMAGE_NAME}:${VERSION}"
echo "   Or for latest fixes: image: ${IMAGE_NAME}:latest-fixed" 