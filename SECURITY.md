# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT** open a public issue
2. Use [GitHub's private vulnerability reporting](https://github.com/mondominator/beamlet/security/advisories/new) or email security concerns to the repository owner
3. Include steps to reproduce the issue
4. Allow reasonable time for a fix before public disclosure

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |

## Security Considerations

- All API endpoints require Bearer token authentication
- Tokens are bcrypt-hashed in the database
- File uploads are validated and size-limited
- Push notification keys should be stored securely and never committed to version control
- The server should be deployed behind a reverse proxy with TLS
