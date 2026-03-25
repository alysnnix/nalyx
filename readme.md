# Nalyx

Personal NixOS configuration (dotfiles/rice) with multi-host support: desktop, laptop, WSL, VM, and homelab.

Built with **Flakes**, **Home-Manager**, **SOPS-nix** for secrets management, and a **public/private split** so the repo can be shared without leaking personal data.

## Quick Start

```bash
# Build and switch (auto-detects private repo if present)
up

# Or manually
sudo nixos-rebuild switch --flake .#desktop
```

## Architecture: Public / Private Split

```
~/
├── nalyx/                  # PUBLIC repo (this one)
│   ├── flake.nix           # Entry point - detects private repo automatically
│   ├── vars.nix            # Safe defaults (user@example.com, empty keys)
│   ├── private/            # Empty placeholder (keeps flake happy)
│   ├── hosts/              # Per-machine configurations
│   │   ├── desktop/        # Main PC (NVIDIA, gaming)
│   │   ├── laptop/         # Notebook (Intel)
│   │   ├── wsl/            # Windows Subsystem for Linux
│   │   ├── vm/             # Virtual machine
│   │   └── homelab/        # Headless server (Tailscale only)
│   ├── home/               # Home-Manager configs
│   │   └── features/       # Modules by category
│   │       ├── cli/        # CLI tools (zsh, git, ssh)
│   │       ├── desktop/    # Desktop environments (hyprland, gnome)
│   │       ├── languages/  # Dev languages (node, python, go, nix)
│   │       └── programs/   # Apps (firefox, vscode, docker)
│   ├── modules/            # Reusable NixOS modules
│   │   ├── core/           # Base system config
│   │   ├── desktop/        # Desktop modules (hyprland, gnome)
│   │   ├── drivers/        # Hardware drivers (nvidia, intel)
│   │   └── secureboot/     # Secure Boot (lanzaboote)
│   └── generators/         # ISO generation
│
└── nalyx-private/          # PRIVATE repo (optional)
    ├── vars-override.nix   # Real email, SSH keys, GitHub username
    ├── secrets/             # SOPS-encrypted secrets (passwords, tokens)
    │   └── secrets.yaml
    ├── scripts/             # Private shell scripts
    └── .sops.yaml           # SOPS encryption rules
```

### How It Works

The `flake.nix` checks if `nalyx-private/vars-override.nix` exists:

- **With private repo**: Merges `vars-override.nix` over defaults, enables SOPS secrets, loads private scripts
- **Without private repo**: Uses safe defaults from `vars.nix`, sets `initialPassword = "changeme"`, skips SOPS entirely

Modules receive `hasPrivate` and `private` as arguments, and use them to conditionally enable features.

## Setup

### 1. Clone the repositories side by side

```bash
cd ~
git clone https://github.com/<your-username>/nalyx.git
git clone git@github.com:<your-username>/nalyx-private.git  # optional
```

### 2. Build

```bash
cd ~/nalyx

# Without private repo (safe defaults)
sudo nixos-rebuild switch --flake .#desktop

# With private repo (auto-detected by the `up` command)
up
```

### Alternative: Lock Private Permanently

Instead of relying on auto-detection at build time, you can lock the private input:

```bash
nix flake lock --override-input private git+ssh://git@github.com/<your-username>/nalyx-private
```

This writes the private repo reference into `flake.lock`. Subsequent `nix flake update` will pull it automatically.

## Fork and Personalize

1. **Fork this repository**
2. **Edit `vars.nix`** with your information (or create a private repo with `vars-override.nix`)
3. **Replace hardware configs** for your machines:
   ```bash
   sudo nixos-generate-config --show-hardware-config > hosts/<host>/hardware-configuration.nix
   ```
4. **Set up SOPS** (see below) if you want encrypted secrets

## Setting Up SOPS Secrets

SOPS encrypts secrets so they can live safely in your private repo.

1. **Generate your Age key from your SSH key:**
   ```bash
   nix-shell -p ssh-to-age --run "ssh-to-age < ~/.ssh/id_ed25519.pub"
   ```

2. **Create `.sops.yaml` in your private repo** with your Age public key:
   ```yaml
   keys:
     - &user_you age1your_public_key_here
   creation_rules:
     - path_regex: secrets/.*\.yaml$
       key_groups:
         - age:
             - *user_you
   ```

3. **Create secrets:**
   ```bash
   cd ~/nalyx-private
   sops secrets/secrets.yaml
   ```

4. **Generate a hashed password:**
   ```bash
   nix-shell -p mkpasswd --run "mkpasswd -m sha-512"
   ```

## Available Hosts

| Host | Description | Desktop | Extras |
|------|-------------|---------|--------|
| `desktop` | Main PC | Hyprland / GNOME | NVIDIA drivers, Steam, gaming |
| `laptop` | Notebook | Hyprland / GNOME | Intel drivers |
| `wsl` | WSL2 | None | Docker Desktop integration |
| `vm` | Test VM | Hyprland / GNOME | Minimal config |
| `homelab` | Server | None | Tailscale-only, SSH, headless |

## Stack

| Layer | Technologies |
|-------|-------------|
| System | NixOS, Flakes, Home-Manager |
| Desktop | Hyprland, GNOME |
| Secrets | SOPS-nix, Age |
| Boot | Lanzaboote (Secure Boot), systemd-boot |
| Shell | Zsh, Oh-My-Zsh |
| Drivers | NVIDIA, Intel |

## Development

```bash
# Enter dev shell (activates pre-commit hooks)
nix develop

# Format all Nix files
nix fmt

# Validate configuration (no build, fast check)
nix flake check --no-build

# Dry-run rebuild
sudo nixos-rebuild dry-run --flake .#desktop

# Update all flake inputs
nix flake update

# Update a single input
nix flake update nixpkgs

# Edit secrets (from private repo)
cd ~/nalyx-private && sops secrets/secrets.yaml
```

Pre-commit hooks (activated via `nix develop`):

- **nixfmt** - Code formatting
- **statix** - Nix linter
- **deadnix** - Dead code detection

## License

This is a personal configuration. Feel free to fork and adapt it to your needs.
