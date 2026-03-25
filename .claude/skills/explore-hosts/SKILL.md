---
name: explore-hosts
description: "Explore host configurations. Use for debugging specific hosts, understanding differences between desktop/laptop/wsl, or modifying machine configurations."
user-invocable: true
---

# Hosts Configuration

## Overview

| Aspect | Value |
|--------|-------|
| Directory | `hosts/` |
| Entry Point | `hosts/<hostname>/default.nix` |
| Assembly | `flake.nix` → `fnMountSystem` |

## Available Hosts

| Host | Hardware | Desktop | Special |
|------|----------|---------|---------|
| `desktop` | NVIDIA | Hyprland/GNOME | Steam, Gaming |
| `laptop` | Intel | Hyprland/GNOME | - |
| `wsl` | Virtual | - | Docker Desktop, WSL2 |
| `vm` | Virtual | Hyprland/GNOME | Testing |

## Host Structure

```
hosts/<hostname>/
├── default.nix              # Main configuration
└── hardware-configuration.nix  # Auto-generated (DO NOT EDIT)
```

## Key Files

```
hosts/desktop/default.nix    # Main PC, NVIDIA, gaming
hosts/laptop/default.nix     # Notebook
hosts/wsl/default.nix        # WSL2 config
hosts/vm/default.nix         # VM for testing
```

## Host Pattern

```nix
{ vars, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core/default.nix
    ../../modules/drivers/<driver>.nix
  ] ++ (lib.optional (vars.desktop == "gnome") ../../modules/desktop/gnome.nix);

  networking.hostName = "<hostname>";
  home-manager.users.${vars.user.name} = import ../../home;
}
```

## Differences Between Hosts

### Desktop vs Laptop

- **Desktop**: NVIDIA driver, Steam, GRUB with OS-Prober
- **Laptop**: Intel driver, default systemd-boot

### WSL vs Native

- **WSL**: No desktop, no graphical drivers, Docker Desktop
- **Native**: Full desktop, drivers, home-manager GUI

## How to Add a New Host

1. Create directory `hosts/<new>/`
2. Generate hardware-config: `nixos-generate-config --show-hardware-config`
3. Create `default.nix` following the pattern
4. Add in `flake.nix`:

```nix
nixosConfigurations = {
  new = fnMountSystem { hostname = "new"; };
};
```

## Useful Commands

```bash
# Rebuild a specific host
sudo nixos-rebuild switch --flake .#desktop

# Dry-run (verify without applying)
sudo nixos-rebuild dry-run --flake .#laptop

# Build without switching
sudo nixos-rebuild build --flake .#vm
```

## isWsl Variable

```nix
# Automatically defined in flake.nix
isWsl = true;  # Only for the wsl host

# Used in home/default.nix for conditional imports
++ lib.optionals (!isWsl) [ ./features/programs ];
```
