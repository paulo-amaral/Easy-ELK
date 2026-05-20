# Security Policy

## Supported Use

Easy-ELK is designed for local labs, demos, and single-node test installs.

By default, the local and sandbox profiles disable Elastic security to keep first-run testing simple. Do not expose these defaults to the public internet.

## Before Production Use

- Enable Elastic security.
- Use TLS for Elasticsearch, Kibana, and reverse proxies.
- Set strong unique passwords.
- Restrict firewall rules to trusted networks.
- Review generated Apache/Nginx configuration.
- Avoid committing `.env`, certificates, private keys, keystores, downloaded packages, logs, or data directories.

## Reporting A Vulnerability

Please open a private GitHub security advisory if available, or contact the maintainer through the repository owner profile.

Include:

- Affected script or install mode.
- Operating system and version.
- Steps to reproduce.
- Risk or expected impact.

## Secret Handling

This repository includes `.gitignore` rules for common secret and runtime files, but you should still review changes before committing:

```bash
git status --short
git diff --cached
```
