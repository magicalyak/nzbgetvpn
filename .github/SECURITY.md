# Security Policy

## Supported Versions

We actively support and provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| latest  | ✅ Yes             |
| v25.x.x | ✅ Yes             |
| < v25   | ❌ No              |

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please follow these guidelines:

### 🔒 Private Disclosure Process

**DO NOT** create a public GitHub issue for security vulnerabilities.

Instead, please:

1. **Use GitHub Security Advisories**: Go to the [Security tab](https://github.com/magicalyak/nzbgetvpn/security/advisories) of this repository and click "Report a vulnerability"
2. **Fill out the form** with detailed information about the vulnerability:
   - Description of the issue
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if you have one)
   - Your contact information

**Alternative contact method:**
- **Email**: security@noreply.github.com (GitHub will forward to maintainers)
- **Subject line** should include: `[SECURITY] nzbgetvpn vulnerability report`

### 📋 What to Include

Please provide as much information as possible:

- **Vulnerability type** (e.g., privilege escalation, data exposure, etc.)
- **Attack vector** (local, network, etc.)
- **Impact assessment** (confidentiality, integrity, availability)
- **Affected components** (Docker image, configuration, scripts, etc.)
- **Prerequisites** for exploitation
- **Proof of concept** (if safe to share)

### ⏰ Response Timeline

We aim to respond to security reports according to this timeline:

- **Initial Response**: Within 48 hours
- **Investigation**: Within 7 days
- **Fix Development**: Within 30 days (depending on severity)
- **Public Disclosure**: After fix is released and users have time to update

### 🚨 Severity Levels

We classify vulnerabilities using the following severity levels:

#### Critical
- Remote code execution
- Container escape
- Exposure of VPN credentials
- Complete bypass of security controls

#### High  
- Local privilege escalation
- Unauthorized access to NZBGet data
- Network traffic interception
- Significant information disclosure

#### Medium
- Denial of service attacks
- Minor information disclosure
- Configuration bypass

#### Low
- Minor security misconfigurations
- Limited information disclosure

### 🛡️ Security Best Practices

To help secure your deployment:

#### Container Security
- Run containers with non-root user when possible
- Use read-only filesystems where applicable
- Limit container capabilities
- Keep Docker daemon updated

#### Network Security
- Use Docker networks to isolate containers
- Avoid exposing unnecessary ports
- Monitor network traffic
- Use VPN kill switch features

#### Configuration Security
- Store credentials securely (use Docker secrets)
- Regularly rotate VPN credentials
- Use strong, unique passwords
- Review and minimize exposed services

#### Monitoring
- Monitor container logs for suspicious activity
- Set up alerts for VPN disconnections
- Monitor resource usage patterns
- Keep audit logs of configuration changes

### 🔄 Security Updates

Security updates will be:

- **Released** as new Docker image tags
- **Documented** in release notes
- **Communicated** through GitHub releases
- **Backwards compatible** when possible

### ⚠️ Disclosure Policy

We follow coordinated disclosure:

1. **Private notification** to maintainers
2. **Investigation and fix development**
3. **Security advisory publication**
4. **Public disclosure** after fix is available

We ask that you:
- Give us reasonable time to investigate and fix issues
- Avoid exploiting the vulnerability
- Don't access or modify other users' data
- Don't perform actions that could harm service availability

### 🏆 Recognition

We appreciate security researchers who help improve our security:

- **Acknowledgment** in security advisories (if desired)
- **Recognition** in project documentation
- **Gratitude** from the community

### 📞 Contact Information

For security-related inquiries:
- **GitHub Security Advisories**: [Report a vulnerability](https://github.com/magicalyak/nzbgetvpn/security/advisories/new)
- **Email**: security@noreply.github.com (forwarded to repository maintainers)
- **Response Time**: Within 48 hours

---

## Security Features

### Current Security Features
- VPN kill switch to prevent IP leaks
- Encrypted VPN tunneling (OpenVPN/WireGuard)
- Container isolation
- Non-privileged execution where possible
- Secure credential handling

### Planned Security Enhancements
- Docker secrets integration
- Enhanced certificate validation
- Automated security scanning
- Additional kill switch options
- Security monitoring endpoints

---

Thank you for helping keep nzbgetvpn secure! 🔒 