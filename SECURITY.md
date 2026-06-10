# Security Policy

## Supported Versions

| Version | Supported          | Notes                |
|--------|-------------------|----------------------|
| v1.1.0 | ✅ Latest         | Current version      |
| v1.0.0 | ❌ End of Life    | Upgrade to v1.1.0   |

## Reporting a Vulnerability

We take security seriously. If you believe you've found a security vulnerability in this GitHub Action, please report it to us through private disclosure.

### How to Report

1. **Do not** create a public issue
2. **Do not** disclose the vulnerability publicly
3. Send an email to [sulthonzh@gmail.com](mailto:sulthonzh@gmail.com) with:
   - Description of the vulnerability
   - Steps to reproduce
   - Expected vs actual behavior
   - Any relevant logs or screenshots
   - Your GitHub username (for attribution)

### Response Time

We aim to:
- Acknowledge your report within 24 hours
- Provide an initial assessment within 3 business days
- Fix critical vulnerabilities within 7 business days
- Provide regular updates on the progress

### Security Features

This action includes several security measures:

#### Input Validation
- **Shell Injection Protection**: Blocks dangerous shell metacharacters
- **Path Traversal Protection**: Prevents `../` attacks
- **Numeric Validation**: Ensures numeric inputs are valid numbers
- **Size Limits**: Prevents buffer overflow attacks

#### SSH Security
- **Key Management**: Secure handling of SSH credentials
- **Connection Security**: Proper SSH configuration
- **Cleanup**: Automatic removal of sensitive data

#### Docker Security
- **Non-root Execution**: Runs with reduced privileges
- **Secure Context Management**: Proper cleanup of Docker contexts
- **Registry Security**: Secure handling of registry credentials

## Security Best Practices

### For Users

1. **Use SSH Keys**: Always use SSH keys instead of passwords
2. **Restrict Host Access**: Only allow trusted remote hosts
3. **Use Secrets**: Store sensitive data as GitHub secrets
4. **Network Security**: Use VPN or private networks when possible
5. **Regular Updates**: Keep the action updated to the latest version

### For Administrators

1. **Monitor Usage**: Track action usage in your organization
2. **Audit Logs**: Review GitHub Actions logs regularly
3. **Access Control**: Implement proper repository access controls
4. **Secret Scanning**: Use secret scanning tools to detect exposed credentials

## Known Limitations

1. **SSH Host Keys**: The action disables strict host key checking for automation
2. **File Permissions**: Files are created with specific permissions for security
3. **Registry Credentials**: Credentials are temporary and securely handled

## Code Security

The codebase follows security best practices:

- **Input Sanitization**: All user inputs are validated and sanitized
- **Command Separation**: Commands are executed safely without shell injection
- **Error Handling**: Proper error handling without information leakage
- **Dependency Management**: Dependencies are kept up to date
- **Code Review**: All changes are reviewed for security implications

## Third-Party Dependencies

This action uses the following third-party components:

- **Docker**: Official Docker image
- **Docker Compose**: Official Docker Compose binary
- **OpenSSH**: OpenSSH client for secure connections

All dependencies are regularly updated to address security issues.

## Compliance

This action is designed to help with security best practices but does not guarantee compliance with specific regulatory requirements. Users are responsible for ensuring compliance with their relevant regulations.

## Questions?

If you have questions about security or this policy, please contact us at [sulthonzh@gmail.com](mailto:sulthonzh@gmail.com).