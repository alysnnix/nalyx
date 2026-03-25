---
name: explore-modules
description: "Explore NixOS modules. Use for system debugging, drivers, desktop modules, or core config."
user-invocable: true
---

# NixOS Modules

## Overview

| Aspect | Value |
|--------|-------|
| Directory | `modules/` |
| Types | core, desktop, drivers, secureboot |

## Structure

```
modules/
├── core/                 # Base system configuration
│   └── default.nix       # Nix settings, users, base packages
├── desktop/              # Graphical environment modules
│   ├── gnome.nix         # GNOME Desktop
│   └── hyprland.nix      # Hyprland compositor
├── drivers/              # Hardware drivers
│   ├── nvidia.nix        # NVIDIA GPU
│   └── intel.nix         # Intel GPU
└── secureboot/           # Secure Boot (Lanzaboote)
    └── default.nix
```

## Core Module

### Location

```
modules/core/default.nix
```

### What It Configures

| Category | Configuration |
|----------|---------------|
| Nix | Flakes, auto-optimise, gc |
| Boot | systemd-boot, kernel modules |
| Network | NetworkManager, Tailscale |
| Users | Main user, groups |
| Shell | ZSH as default |
| Secrets | SOPS-nix |
| Fonts | JetBrains Mono, Fira Code |

### Kernel Modules

```nix
kernelModules = [
  "v4l2loopback"  # OBS Virtual Camera
  "it87"          # Gigabyte sensors
  "coretemp"      # CPU temperature
];
```

## NVIDIA Module

### Location

```
modules/drivers/nvidia.nix
```

### Configurations

- Proprietary driver
- Modesetting
- Power management
- CUDA support

### Used By

- `hosts/desktop/default.nix`

## Intel Module

### Location

```
modules/drivers/intel.nix
```

### Used By

- `hosts/laptop/default.nix`

## Desktop Modules

### GNOME

```
modules/desktop/gnome.nix
```

- GDM display manager
- GNOME shell
- Basic extensions

### Hyprland

```
modules/desktop/hyprland.nix
```

- Hyprland compositor
- XDG portals
- Wayland session

### Conditional Selection

```nix
# In hosts/<host>/default.nix
imports = [
] ++ (lib.optional (vars.desktop == "gnome") ../../modules/desktop/gnome.nix)
  ++ (lib.optional (vars.desktop == "hyprland") ../../modules/desktop/hyprland.nix);
```

## Secure Boot

### Location

```
modules/secureboot/default.nix
```

### Uses

- Lanzaboote for secure boot
- TPM2 support

## How to Add a New Module

### 1. Create File

```bash
touch modules/<category>/<name>.nix
```

### 2. Basic Structure

```nix
{ pkgs, vars, lib, config, ... }:
{
  # Module configurations
}
```

### 3. Import in the Host

```nix
# hosts/<host>/default.nix
imports = [
  ../../modules/<category>/<name>.nix
];
```

## Common Patterns

### Conditional Module

```nix
{ lib, config, ... }:
{
  config = lib.mkIf config.programs.name.enable {
    # Configurations when enabled
  };
}
```

### Module with Options

```nix
{ lib, ... }:
{
  options.my-module = {
    enable = lib.mkEnableOption "My module";
  };

  config = lib.mkIf config.my-module.enable {
    # Configurations
  };
}
```
