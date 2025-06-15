#!/bin/bash
set -e

# Configuration
VERSION="v25.0.30"
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
    git commit -m "docs: Release ${VERSION} - VPN credentials documentation fixes

- Fixed critical VPN credentials file naming inconsistency
- Container now accepts both credentials.txt and credentials.conf
- Added security guidance for file-based vs environment variable auth
- Enhanced troubleshooting documentation with correct examples
- Updated .env.sample with both authentication methods

Prevents VPN authentication failures from inconsistent documentation"
fi

# Create and push tag
echo -e "${BLUE}🏷️  Creating tag ${VERSION}...${NC}"
git tag -a "${VERSION}" -m "Release ${VERSION}

## 🎉 nzbgetvpn ${VERSION} - VPN Credentials Documentation Fixes

### 📖 Documentation Improvements
- **CRITICAL FIX**: Fixed VPN credentials file naming inconsistency
- **Backward Compatibility**: Container now accepts both credentials.txt and credentials.conf
- **Security Enhancement**: Added guidance on file-based vs environment variable authentication
- **Better Examples**: Updated troubleshooting with correct authentication methods
- **Complete Guide**: Enhanced .env.sample with both authentication options

### 🔧 Code Improvements  
- **Flexible Authentication**: Enhanced vpn-setup.sh to handle multiple credential file formats
- **Better Error Messages**: Clearer guidance when credentials are missing
- **Improved Debugging**: More informative logs for authentication issues

### 🚨 What This Fixes
This release prevents VPN authentication failures that occurred when users:
- Created credentials files with different naming conventions
- Followed inconsistent documentation about authentication methods
- Encountered confusing error messages during troubleshooting

### 📝 Authentication Methods
\`\`\`bash
# Method 1: Environment variables (less secure)
VPN_USER=your_username
VPN_PASS=your_password

# Method 2: Credentials file (recommended)
echo \"your_username\" > ~/nzbgetvpn/config/openvpn/credentials.txt
echo \"your_password\" >> ~/nzbgetvpn/config/openvpn/credentials.txt
\`\`\`

See updated README.md and TROUBLESHOOTING.md for complete setup guides."

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