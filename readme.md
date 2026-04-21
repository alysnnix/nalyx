# Nalyx

Personal NixOS configuration with multi-host support: desktop, laptop, WSL, VM, and homelab.

Built with **Flakes**, **Home-Manager**, **SOPS-nix**, and a **public/private split** using composable flake modules.

## Quick Start

```bash
switch          # auto-detects hostname and private repo
switch wsl      # specify a host
```

## Architecture

```
nalyx/ (public)                     nalyx-private/ (optional flake)
├── flake.nix                       ├── flake.nix (exports modules)
├── vars.nix                        ├── nixos/ (SOPS, passwords, secrets)
├── hosts/                          ├── home/ (MCPs, scripts, aliases)
│   ├── desktop/                    └── secrets/secrets.yaml
│   ├── laptop/
│   ├── wsl/
│   ├── vm/
│   └── homelab/
├── modules/ (core, desktop, drivers, services)
├── home/features/ (cli, desktop, languages, programs)
└── ci/empty-private/ (CI placeholder)
```

The private repo is an optional flake that exports NixOS and Home-Manager modules. When present, they overlay config on top of public defaults. When absent, the system builds with safe defaults.

No public module references secrets, private URLs, or knows the private repo exists.

## Hosts

| Host | Description | Desktop | Extras |
|------|-------------|---------|--------|
| `desktop` | Main PC | Hyprland / GNOME | NVIDIA, Steam, gaming |
| `laptop` | Notebook | Hyprland / GNOME | Intel |
| `wsl` | WSL2 | None | Docker Desktop |
| `vm` | Test VM | Hyprland / GNOME | Minimal |
| `homelab` | Server | None | Tailscale, SSH, headless |

## Stack

| Layer | Technologies |
|-------|-------------|
| System | NixOS, Flakes, Home-Manager |
| Desktop | Hyprland (Caelestia), GNOME |
| Secrets | SOPS-nix, Age |
| Boot | Lanzaboote (Secure Boot), systemd-boot |
| Shell | Zsh, Oh-My-Zsh |
| Drivers | NVIDIA, Intel |

## Setup

### 1. Clone

```bash
git clone https://github.com/alysnnix/nalyx.git ~/nalyx
cd ~/nalyx
```

### 2. Private repo (optional)

```bash
git clone git@github.com:alysnnix/nalyx-private.git .private/nalyx-private
```

### 3. Build

```bash
# First time (switch alias doesn't exist yet)
bash home/features/cli/zsh/scripts/update-sys.sh wsl

# After the first rebuild
switch wsl
```

## Development

```bash
nix develop             # Enter dev shell (activates pre-commit hooks)
nix fmt                 # Format all Nix files
nix flake check --no-build  # Validate configurations
```

Pre-commit hooks: **nixfmt**, **statix**, **deadnix**

## License

[GPL-3.0](LICENSE)
