---
name: explore-modules
description: "Explorar módulos NixOS. Use para debug de sistema, drivers, desktop modules, ou core config."
user-invocable: true
---

# NixOS Modules

## Overview

| Aspecto | Valor |
|---------|-------|
| Diretório | `modules/` |
| Tipos | core, desktop, drivers, secureboot |

## Estrutura

```
modules/
├── core/                 # Configuração base do sistema
│   └── default.nix       # Nix settings, users, packages base
├── desktop/              # Módulos de ambiente gráfico
│   ├── gnome.nix         # GNOME Desktop
│   └── hyprland.nix      # Hyprland compositor
├── drivers/              # Drivers de hardware
│   ├── nvidia.nix        # NVIDIA GPU
│   └── intel.nix         # Intel GPU
└── secureboot/           # Secure Boot (Lanzaboote)
    └── default.nix
```

## Módulo Core

### Localização

```
modules/core/default.nix
```

### O Que Configura

| Categoria | Configuração |
|-----------|--------------|
| Nix | Flakes, auto-optimise, gc |
| Boot | systemd-boot, kernel modules |
| Rede | NetworkManager, Tailscale |
| Users | User principal, grupos |
| Shell | ZSH como padrão |
| Secrets | SOPS-nix |
| Fonts | JetBrains Mono, Fira Code |

### Kernel Modules

```nix
kernelModules = [
  "v4l2loopback"  # OBS Virtual Camera
  "it87"          # Sensores Gigabyte
  "coretemp"      # Temperatura CPU
];
```

## Módulo NVIDIA

### Localização

```
modules/drivers/nvidia.nix
```

### Configurações

- Driver proprietário
- Modesetting
- Power management
- CUDA support

### Usado Por

- `hosts/desktop/default.nix`

## Módulo Intel

### Localização

```
modules/drivers/intel.nix
```

### Usado Por

- `hosts/laptop/default.nix`

## Módulos Desktop

### GNOME

```
modules/desktop/gnome.nix
```

- GDM display manager
- GNOME shell
- Extensões básicas

### Hyprland

```
modules/desktop/hyprland.nix
```

- Hyprland compositor
- XDG portals
- Wayland session

### Seleção Condicional

```nix
# Em hosts/<host>/default.nix
imports = [
] ++ (lib.optional (vars.desktop == "gnome") ../../modules/desktop/gnome.nix)
  ++ (lib.optional (vars.desktop == "hyprland") ../../modules/desktop/hyprland.nix);
```

## Secure Boot

### Localização

```
modules/secureboot/default.nix
```

### Usa

- Lanzaboote para boot seguro
- TPM2 support

## Como Adicionar Novo Módulo

### 1. Criar Arquivo

```bash
touch modules/<categoria>/<nome>.nix
```

### 2. Estrutura Básica

```nix
{ pkgs, vars, lib, config, ... }:
{
  # Configurações do módulo
}
```

### 3. Importar no Host

```nix
# hosts/<host>/default.nix
imports = [
  ../../modules/<categoria>/<nome>.nix
];
```

## Padrões Comuns

### Módulo Condicional

```nix
{ lib, config, ... }:
{
  config = lib.mkIf config.programs.nome.enable {
    # Configurações quando habilitado
  };
}
```

### Módulo com Options

```nix
{ lib, ... }:
{
  options.meu-modulo = {
    enable = lib.mkEnableOption "Meu módulo";
  };

  config = lib.mkIf config.meu-modulo.enable {
    # Configurações
  };
}
```
