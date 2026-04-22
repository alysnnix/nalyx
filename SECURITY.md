# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

**Do NOT open a public issue.**

Instead, email: aly@alysnnix.dev

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact

I will respond within 48 hours and work on a fix.

## Scope

This is a personal NixOS configuration. Security concerns include:
- Secrets leaking into the public repository
- Insecure default configurations
- Vulnerable package versions

## Design

- Secrets are managed via SOPS-nix in a separate private repository
- The public repo contains no API keys, tokens, or credentials
- All sensitive configuration is injected at build time via private flake modules
