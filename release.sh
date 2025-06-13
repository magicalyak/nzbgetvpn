#!/bin/bash
set -e

# Configuration
VERSION="v25.0.25"
IMAGE_NAME="magicalyak/nzbgetvpn"
BRANCH="main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 nzbgetvpn Release Script${NC}"
echo -e "${BLUE}=============================${NC}"
echo -e "Version: ${GREEN}${VERSION}${NC}"
echo -e "Image:   ${GREEN}${IMAGE_NAME}${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi

# Check if we're on the right branch
current_branch=$(git branch --show-current)
if [[ "$current_branch" != "$BRANCH" ]]; then
    echo -e "${RED}❌ Not on $BRANCH branch. Current branch: $current_branch${NC}"
    echo -e "   Switch to $BRANCH branch: ${YELLOW}git checkout $BRANCH${NC}"
    exit 1
fi

# Check if tag already exists
if git tag -l | grep -q "^${VERSION}$"; then
    echo -e "${RED}❌ Tag ${VERSION} already exists!${NC}"
    echo -e "   To recreate: ${YELLOW}git tag -d ${VERSION} && git push origin :refs/tags/${VERSION}${NC}"
    exit 1
fi

# Check for uncommitted changes
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${YELLOW}⚠️  Uncommitted changes detected:${NC}"
    git status --short
    echo ""
    read -p "Continue with uncommitted changes? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ Aborted. Please commit your changes first.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Build the image
echo -e "${YELLOW}📦 Building Docker image...${NC}"
./build-fixed.sh

echo ""
echo -e "${YELLOW}🏷️  Creating Git tag...${NC}"

# Create commit if there are changes
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${BLUE}📝 Committing changes...${NC}"
    git add .
    git commit -m "fix: Release ${VERSION} - BusyBox compatibility and monitoring improvements

- Fixed BusyBox grep compatibility issues in health check script
- Enhanced Prometheus monitoring with comprehensive metrics
- Added proper device mapping for VPN functionality
- Improved documentation with monitoring guides
- Updated Docker Compose with required configurations

Fixes issues with health checks showing 'unknown' status
Resolves VPN connectivity problems on various platforms"
fi

# Create and push tag
echo -e "${BLUE}🏷️  Creating tag ${VERSION}...${NC}"
git tag -a "${VERSION}" -m "Release ${VERSION}

## 🎉 nzbgetvpn ${VERSION} - BusyBox Compatibility & Monitoring Improvements

### 🐛 Bug Fixes
- **BusyBox grep compatibility** - Health checks now work on all Linux distributions
- **VPN interface detection** - Proper IP address extraction across platforms  
- **Device mapping** - Fixed /dev/net/tun configuration issues

### ✨ Improvements
- **Enhanced Prometheus integration** - Complete monitoring with /prometheus endpoint
- **Better health endpoints** - /health, /prometheus, /status, /metrics
- **Updated documentation** - Complete monitoring and setup guides
- **Improved Docker Compose** - Includes all required configurations

### 📊 Monitoring
- Health: http://localhost:8080/health
- Prometheus: http://localhost:8080/prometheus
- Status: http://localhost:8080/status

### 🔧 Migration
\`\`\`yaml
# docker-compose.yml
services:
  nzbgetvpn:
    image: ${IMAGE_NAME}:${VERSION}
    devices:
      - /dev/net/tun  # Required!
    ports:
      - \"8080:8080\"  # Monitoring
\`\`\`

See MONITORING.md for complete setup guide."

echo -e "${GREEN}✅ Git tag created successfully${NC}"
echo ""

# Show next steps
echo -e "${BLUE}🚀 Release Summary${NC}"
echo -e "${BLUE}==================${NC}"
echo -e "Version:     ${GREEN}${VERSION}${NC}"
echo -e "Git tag:     ${GREEN}Created locally${NC}"
echo -e "Docker tags: ${GREEN}Built locally${NC}"
echo ""
echo -e "${YELLOW}📤 Next Steps:${NC}"
echo -e "1. Push the Git tag:    ${BLUE}git push origin ${VERSION}${NC}"
echo -e "2. Push Docker images:  ${BLUE}docker push ${IMAGE_NAME}:${VERSION}${NC}"
echo -e "                        ${BLUE}docker push ${IMAGE_NAME}:latest-fixed${NC}"
echo -e "                        ${BLUE}docker push ${IMAGE_NAME}:v25-fixed${NC}"
echo -e "3. Create GitHub release from tag: ${BLUE}https://github.com/magicalyak/nzbgetvpn/releases/new?tag=${VERSION}${NC}"
echo ""
echo -e "${GREEN}🎉 Release ${VERSION} is ready!${NC}"

# Ask if user wants to push automatically
echo ""
read -p "Push Git tag and Docker images now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}📤 Pushing Git tag...${NC}"
    git push origin "${VERSION}"
    
    echo -e "${YELLOW}📤 Pushing Docker images...${NC}"
    docker push "${IMAGE_NAME}:${VERSION}"
    docker push "${IMAGE_NAME}:latest-fixed"
    docker push "${IMAGE_NAME}:v25-fixed"
    
    echo ""
    echo -e "${GREEN}🎉 Release ${VERSION} published successfully!${NC}"
    echo -e "GitHub Release: ${BLUE}https://github.com/magicalyak/nzbgetvpn/releases/new?tag=${VERSION}${NC}"
    echo -e "Docker Hub:     ${BLUE}https://hub.docker.com/r/magicalyak/nzbgetvpn/tags${NC}"
else
    echo -e "${YELLOW}ℹ️  Manual push required. Run the commands above when ready.${NC}"
fi 