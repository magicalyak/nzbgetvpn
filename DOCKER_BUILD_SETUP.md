# Docker Build Setup Guide

## Recommended Configuration

### 1. Docker Hub Settings

**DISABLE Docker Hub Autobuild** - We use GitHub Actions for all builds

Your Docker Hub repository (`magicalyak/nzbgetvpn`) should have:
- ❌ Autobuild: **OFF** (currently shows configured for 'master' branch which doesn't exist)
- ❌ Repository Links: **OFF**
- ✅ Allow GitHub Actions to push images via Docker Hub token

### 2. GitHub Actions Handles All Builds

Our GitHub Actions workflow (`build-and-publish.yml`) manages:
- Multi-architecture builds (amd64, arm64)
- Version tagging
- Security scanning with Trivy
- Pushing to both Docker Hub and GitHub Container Registry

### 3. Build Triggers

Builds are triggered by:
- **Version tags** (`v*`) - Creates release builds
- **Manual dispatch** - For testing

### 4. Security Scanning

We use two security scanning tools:

#### Trivy (Currently Active)
- Runs on every build
- Reports to GitHub Security tab
- Scans for CVEs in OS packages and application dependencies

#### Docker Scout (Recommended Addition)
To enable Docker Scout:

1. **In Docker Hub:**
   - Go to your repository settings
   - Enable Docker Scout under "Image Analysis"
   - This provides:
     - CVE scanning
     - Base image recommendations
     - SBOM generation
     - License scanning

2. **Local Scanning:**
   ```bash
   # Install Docker Scout CLI
   curl -sSfL https://raw.githubusercontent.com/docker/scout-cli/main/install.sh | sh -s --

   # Scan an image
   docker scout cves magicalyak/nzbgetvpn:latest
   docker scout recommendations magicalyak/nzbgetvpn:latest
   ```

### 5. Version Management

See [VERSIONING.md](VERSIONING.md) for our versioning strategy.

### 6. Release Process

1. **Update version and create tag:**
   ```bash
   git tag v25.0.44
   git push origin v25.0.44
   ```

2. **GitHub Actions automatically:**
   - Builds multi-architecture images
   - Runs security scans
   - Pushes to registries with proper tags
   - Updates `latest` and `stable` tags

3. **Monitor build:**
   - Check [Actions tab](https://github.com/magicalyak/nzbgetvpn/actions)
   - Verify images on [Docker Hub](https://hub.docker.com/r/magicalyak/nzbgetvpn)

### 7. Troubleshooting

#### Build Not Triggering
- Ensure tag starts with 'v'
- Check GitHub Actions is enabled in repository settings

#### Security Scan Errors
- Trivy cache may need clearing
- Check Trivy version in workflow

#### Docker Hub Not Updating
- Verify Docker Hub token in GitHub Secrets
- Check for rate limiting

### 8. Best Practices

1. **Never enable both** Docker Hub Autobuild and GitHub Actions builds
2. **Use GitHub Actions** as the single source of truth for builds
3. **Monitor security scans** regularly
4. **Update base images** monthly for security patches
5. **Test locally** before creating release tags