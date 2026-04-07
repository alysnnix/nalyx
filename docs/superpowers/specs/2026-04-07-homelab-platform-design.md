# Homelab App Platform

**Date:** 2026-04-07
**Status:** Draft

## Problem

Deploy web applications (starting with a Django project) on the homelab without opening router ports and without compromising the local network. Need a reusable, declarative module so future apps can be added with minimal config.

## Constraints

- Hardware: Intel 7th gen, 12GB RAM (tight — no Kata for new apps)
- OpenClaw already runs with Kata containers — leave it unchanged
- App repos are private on GitHub — use homelab's existing SSH key (`~/.ssh/id_ed25519`)
- Secrets (env files, tunnel credentials) managed via SOPS in nalyx-private
- Must follow existing NixOS module patterns (see CLAUDE.md)

## Architecture

```
Internet
  │
  ▼
Cloudflare (WAF + HTTPS + Access)
  │
  ▼ (outbound tunnel, zero inbound ports)
cloudflared daemon (homelab)
  │
  ├── app1.domain.com → localhost:8000 (Django)
  ├── app2.domain.com → localhost:3000 (future)
  └── catch-all → 404
        │
        ▼
Docker containers (hardened, no Kata)
on isolated bridge network (br-homelab)
  │
  ├── django-app ←→ django-db (PostgreSQL)
  ├── future-app ←→ future-db
  └── ... (each app brings its own DB)
```

### Network Isolation

Single shared bridge `br-homelab` (subnet `172.31.0.0/24`) for all platform apps. Containers can talk to each other within the bridge but cannot reach LAN, host, or Tailscale.

Firewall rules (same pattern as openclaw):

```
DOCKER-USER chain:
  br-homelab → 10.0.0.0/8      DROP
  br-homelab → 172.16.0.0/12   DROP
  br-homelab → 192.168.0.0/16  DROP
  br-homelab → 169.254.0.0/16  DROP
  br-homelab → 100.64.0.0/10   DROP  (Tailscale)

INPUT chain:
  br-homelab → host             DROP

IPv6:
  br-homelab                    DROP (all)
```

### Security Layers

```
Layer 1: Cloudflare WAF (filters malicious traffic before it reaches homelab)
Layer 2: Cloudflare Access (GitHub/Google login on protected routes like /admin)
Layer 3: Isolated Docker network (no LAN/host/Tailscale access)
Layer 4: Container hardening (--cap-drop ALL, --read-only, --security-opt no-new-privileges)
Layer 5: Resource limits (memory, CPU, PID limits per container)
```

## Module Structure

```
modules/services/
├── openclaw.nix                        # Unchanged
├── homelab-platform/
│   ├── default.nix                     # Module options + imports
│   ├── cloudflared.nix                 # Single tunnel daemon, YAML config generated from apps
│   ├── network.nix                     # Docker network + firewall rules
│   └── app.nix                         # Generic per-app logic via mapAttrs
```

### NixOS Options

```nix
options.services.homelab-platform = {
  enable = lib.mkEnableOption "Homelab app platform";

  tunnel = {
    credentialsFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to cloudflared tunnel credentials JSON (from SOPS)";
    };
    tunnelId = lib.mkOption {
      type = lib.types.str;
      description = "Cloudflare Tunnel ID";
    };
  };

  apps = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        repo = lib.mkOption {
          type = lib.types.str;
          description = "Git SSH URL of the app repository";
        };
        domain = lib.mkOption {
          type = lib.types.str;
          description = "Public domain routed via Cloudflare Tunnel";
        };
        port = lib.mkOption {
          type = lib.types.port;
          description = "Port the app listens on inside the container";
        };
        envFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to .env file (from SOPS)";
        };
        memory = lib.mkOption {
          type = lib.types.str;
          default = "1g";
          description = "Docker memory limit";
        };
        cpus = lib.mkOption {
          type = lib.types.str;
          default = "1";
          description = "Docker CPU limit";
        };
      };
    });
    default = {};
    description = "Apps to deploy on the platform";
  };
};
```

### Usage Example

```nix
# In hosts/homelab/default.nix
services.homelab-platform = {
  enable = true;
  tunnel = {
    credentialsFile = config.sops.secrets.cloudflared-creds.path;
    tunnelId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx";
  };

  apps.django = {
    repo = "git@github.com:aly/meu-django.git";
    domain = "app.meudominio.com";
    port = 8000;
    envFile = config.sops.secrets.django-env.path;
    memory = "1g";
    cpus = "1";
  };
};
```

Adding a future app:

```nix
  apps.outro = {
    repo = "git@github.com:aly/outro.git";
    domain = "outro.meudominio.com";
    port = 3000;
    envFile = config.sops.secrets.outro-env.path;
  };
```

### Secrets (nalyx-private)

```yaml
# In secrets/secrets.yaml
cloudflared_tunnel_creds: '{"AccountTag":"...","TunnelSecret":"...","TunnelID":"..."}'
django_env: |
  SECRET_KEY=...
  DATABASE_URL=postgres://django:pass@django-db:5432/django
  ALLOWED_HOSTS=app.meudominio.com
```

## What Each Module Does

### default.nix

- Defines the `services.homelab-platform` option set
- Imports cloudflared.nix, network.nix, app.nix
- Only activates when `enable = true`

### network.nix

- Creates Docker network `homelab-apps` with bridge `br-homelab` (subnet `172.31.0.0/24`)
- Disables IPv6 on the bridge
- Adds iptables rules to DOCKER-USER and INPUT chains (identical pattern to openclaw)
- Adds cleanup rules to `extraStopCommands`

### cloudflared.nix

- Generates `/etc/cloudflared/config.yml` from the apps attrset:
  ```yaml
  tunnel: <tunnelId>
  credentials-file: <credentialsFile>
  ingress:
    - hostname: app.meudominio.com
      service: http://localhost:8000
    - hostname: outro.meudominio.com
      service: http://localhost:3000
    - service: http_status:404
  ```
- Runs `cloudflared tunnel run` as a systemd service
- Depends on network service

### app.nix

For each entry in `apps`, generates via `mapAttrs`:

**PostgreSQL container:**
- Image: `postgres:16-alpine`
- Network: `homelab-apps`
- Container name: `<app>-db`
- Volume: `/var/lib/homelab/<app>/postgres` → `/var/lib/postgresql/data`
- Hardened: `--cap-drop ALL` (with `CAP_SETUID`, `CAP_SETGID`, `CAP_FOWNER`, `CAP_DAC_OVERRIDE` added back — required by postgres), `--security-opt no-new-privileges`
- Memory: 512MB default
- No port binding (only accessible within isolated network)

**App container:**
- Image: built from repo Dockerfile
- Network: `homelab-apps`
- Container name: `<app>`
- Port: `127.0.0.1:<port>:<port>` (only localhost, cloudflared connects here)
- Volume: `/var/lib/homelab/<app>/data` → `/app/data` (persistent uploads, media)
- Env file from SOPS
- Hardened: `--cap-drop ALL`, `--read-only`, `--security-opt no-new-privileges`, `--tmpfs /tmp`
- Resource limits from config (memory, cpus)
- DNS: `1.1.1.1`, `9.9.9.9`
- PID limit: 256

**Update script:**
- `update-<app>`: pulls repo, rebuilds image, restarts service
- Uses homelab's SSH key for git operations (`GIT_SSH_COMMAND` with `/home/<user>/.ssh/id_ed25519`)

**Systemd ordering:**
```
docker.service
  → docker-network-homelab.service
    → <app>-db.service
      → <app>.service
        → cloudflared.service
```

## Cloudflare Access (Manual Setup)

Configured in the Cloudflare Zero Trust dashboard (not in NixOS):

1. Create an Access Application for `app.meudominio.com/admin/*`
2. Add a policy: "Allow" → "GitHub" → your GitHub username
3. All other routes remain public

This is a one-time manual step per protected route.

## Cloudflare Tunnel Setup (One-Time)

```bash
# On any machine with cloudflared installed
cloudflared tunnel login
cloudflared tunnel create homelab

# This outputs a credentials JSON — add it to SOPS secrets
# Then add DNS records:
cloudflared tunnel route dns homelab app.meudominio.com
```

## Management Commands

```bash
# Per-app updates
update-django              # Pull, rebuild, restart Django app
update-outro               # Same for another app

# Status
systemctl status django    # App container
systemctl status django-db # Database container
systemctl status cloudflared

# Logs
journalctl -u django -f
journalctl -u cloudflared -f

# Restart
systemctl restart django
```

## Resource Budget (12GB RAM)

| Service | RAM Estimate |
|---------|-------------|
| NixOS base + Tailscale | ~1.5GB |
| OpenClaw (Kata) | ~1.5GB (VM overhead + app) |
| cloudflared | ~50MB |
| Django app | ~256MB |
| Django PostgreSQL | ~256MB |
| Available for future apps | ~8.4GB |

## Out of Scope (Future)

- Monitoring stack (Grafana + Prometheus + Loki)
- Automated database backups
- CI/CD auto-deploy via GitHub webhooks
- Celery/Redis workers
- Health checks and auto-restart on unhealthy
