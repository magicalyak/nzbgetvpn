# Contributing to nzbgetvpn

Thank you for your interest in contributing to nzbgetvpn! This document provides guidelines and information for contributors.

## 🤝 How to Contribute

### Reporting Issues
- Use the appropriate issue template (Bug Report, Feature Request, or Question)
- Search existing issues before creating a new one
- Include detailed information about your environment and configuration
- Provide logs and reproduction steps for bugs

### Suggesting Features
- Use the Feature Request template
- Explain the use case and benefit to other users
- Consider if the feature aligns with the project's goals
- Be open to discussion and alternative approaches

### Contributing Code

#### Getting Started
1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Test thoroughly with different configurations
5. Submit a pull request

#### Development Environment
```bash
# Clone your fork
git clone https://github.com/yourusername/nzbgetvpn.git
cd nzbgetvpn

# Build the Docker image locally
docker build -t nzbgetvpn-dev .

# Test with different configurations
docker-compose up -d
```

#### Code Guidelines
- Follow existing code style and conventions
- Comment complex logic clearly
- Keep changes focused and atomic
- Write descriptive commit messages
- Test with both OpenVPN and WireGuard if applicable

#### Testing
Before submitting a PR, please test:
- Docker image builds successfully
- Container starts without errors
- VPN connection works properly
- NZBGet functions correctly
- No regression in existing functionality

**Recommended Testing Configurations:**
- OpenVPN with different providers
- WireGuard configuration
- Different platform architectures (if possible)
- Various environment variable combinations

## 📋 Pull Request Process

1. **Use the PR template** - Fill out all relevant sections
2. **Link related issues** - Reference any related issues or discussions
3. **Describe your changes** - Explain what you changed and why
4. **Update documentation** - Update README.md if needed
5. **Test thoroughly** - Verify your changes work as expected
6. **Be responsive** - Address feedback and review comments promptly

### PR Review Process
- All PRs require review before merging
- Maintainers may request changes or additional testing
- CI/CD checks must pass
- Breaking changes require special consideration

## 🏷️ Issue Labels

We use the following label system:

**Type Labels:**
- `bug` - Something isn't working
- `enhancement` - New feature or improvement
- `question` - Further information is requested
- `documentation` - Documentation improvements

**Priority Labels:**
- `priority-high` - Critical issues
- `priority-medium` - Important improvements
- `priority-low` - Nice to have features

**Area Labels:**
- `area-vpn` - VPN-related functionality
- `area-nzbget` - NZBGet configuration
- `area-docker` - Docker/containerization
- `area-networking` - Network configuration
- `area-security` - Security-related changes

## 🚀 Development Areas

Looking for ways to contribute? Here are some areas we're actively developing:

### High Priority
- Multi-architecture builds (ARM64 support)
- Enhanced health monitoring
- Security improvements
- VPN provider-specific documentation

### Medium Priority
- Performance optimizations
- Additional configuration options
- Better error handling and logging
- User experience improvements

### Low Priority
- Theme customizations
- Advanced monitoring features
- Integration with other tools

## 🔒 Security

If you discover a security vulnerability, please:
- **DO NOT** create a public issue
- Email the maintainers directly
- Provide detailed information about the vulnerability
- Allow time for the issue to be addressed before public disclosure

## 📜 Code of Conduct

### Our Standards
- Be respectful and inclusive
- Focus on constructive feedback
- Help newcomers learn and contribute
- Maintain a professional tone in all interactions

### Unacceptable Behavior
- Harassment or discrimination
- Spam or off-topic discussions
- Sharing others' private information
- Any behavior that would be inappropriate in a professional setting

## ❓ Getting Help

If you need help contributing:
- Check existing documentation
- Review the [Troubleshooting Guide](../TROUBLESHOOTING.md) for common issues
- Look at recent PRs for examples
- Ask questions in issue discussions
- Reach out to maintainers if needed

## 🙏 Recognition

Contributors are recognized in:
- GitHub contributor graphs
- Release notes for significant contributions
- Project acknowledgments

## 📝 License

By contributing to nzbgetvpn, you agree that your contributions will be licensed under the same license as the project.

---

Thank you for contributing to nzbgetvpn! 🎉 