# Syncthing ~/wrk Sync + SSHFS Access

## Problem

Dual-boot setup (NixOS desktop + Windows/WSL) on same PC. Files created on NixOS desktop are inaccessible from WSL without rebooting. Need a way to sync work files to a central homelab server so any host can access them.

## Architecture

```
desktop  ~/wrk  ──tailscale──→  homelab /data/sync/desktop/wrk  (send-only)
laptop   ~/wrk  ──tailscale──→  homelab /data/sync/laptop/wrk   (send-only)
wsl      ~/wrk  ──tailscale──→  homelab /data/sync/wsl/wrk      (send-only)

homelab: receive-only, btrfs with zstd compression + duperemove dedup
```

All communication happens over Tailscale (no public ports). Homelab DNS: `homelab.alysson.dev` (Cloudflare → Tailscale IP).

## Components

### 1. Syncthing NixOS Module (`modules/services/syncthing.nix`)

Shared module imported by all participating hosts. Configures:

- Syncthing service with correct user/group/paths
- Firewall rules on `tailscale0` interface (ports 8384, 22000 TCP + 22000, 21027 UDP)
- Web UI on `localhost:8384` (all hosts)
- `overrideDevices = false` and `overrideFolders = false` — initial device pairing and folder setup done via web UI, since device IDs are generated at first run

### 2. Homelab Extras (in `hosts/homelab/default.nix`)

- `systemd.tmpfiles.rules` to create `/data/sync/{desktop,laptop,wsl}` directories
- `duperemove` weekly systemd timer for btrfs block-level dedup on `/data/sync`
- `duperemove` package installed

### 3. Host Configs (desktop, laptop, wsl)

Each host imports `../../modules/services/syncthing.nix`. No extra config needed — folder setup via web UI.

### 4. Home-Manager: SSHFS + Aliases (`home/features/cli/zsh/default.nix`)

- `sshfs` package added
- `mount-homelab` alias: mounts `homelab.alysson.dev:/data/sync` to `~/mnt/homelab`
- `umount-homelab` alias: unmounts cleanly
- `.stignore` managed via `home.file` for `~/wrk/.stignore`

### 5. vars.nix Update

Add `homelab.address` with safe default (`homelab.local`). Private repo overrides to `homelab.alysson.dev`.

## .stignore Contents

```
node_modules
.cache
.next
target
dist
__pycache__
.venv
*.tmp
.direnv
.devenv
.terraform
vendor
```

## Files Changed

| File | Action |
|------|--------|
| `modules/services/syncthing.nix` | New — shared Syncthing module |
| `hosts/homelab/default.nix` | Edit — import syncthing, add duperemove timer |
| `hosts/desktop/default.nix` | Edit — import syncthing |
| `hosts/laptop/default.nix` | Edit — import syncthing |
| `hosts/wsl/default.nix` | Edit — import syncthing |
| `home/features/cli/zsh/default.nix` | Edit — sshfs package, aliases, .stignore |
| `vars.nix` | Edit — add homelab.address |

## Out of Scope

- Reformatting homelab disk to btrfs (physical operation, done at reinstall time)
- Fully declarative Syncthing device/folder config (needs device IDs from first run)
- Automatic snapshots (future improvement)

## First Run Setup

After `switch` on all hosts:
1. Open `localhost:8384` on homelab
2. Add each client device (desktop/laptop/wsl) via device ID
3. Share folders: each client's `~/wrk` → homelab's `/data/sync/<hostname>/wrk`
4. Set client folders as "Send Only", homelab folders as "Receive Only"
