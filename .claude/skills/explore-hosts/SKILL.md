---
name: explore-hosts
description: "Explorar configurações de hosts. Use para debug de hosts específicos, entender diferenças entre desktop/laptop/wsl, ou modificar configurações de máquina."
user-invocable: true
---

# Hosts Configuration

## Overview

| Aspecto | Valor |
|---------|-------|
| Diretório | `hosts/` |
| Entry Point | `hosts/<hostname>/default.nix` |
| Montagem | `flake.nix` → `fnMountSystem` |

## Hosts Disponíveis

| Host | Hardware | Desktop | Especial |
|------|----------|---------|----------|
| `desktop` | NVIDIA | Hyprland/GNOME | Steam, Gaming |
| `laptop` | Intel | Hyprland/GNOME | - |
| `wsl` | Virtual | - | Docker Desktop, WSL2 |
| `vm` | Virtual | Hyprland/GNOME | Testes |

## Estrutura de um Host

```
hosts/<hostname>/
├── default.nix              # Configuração principal
└── hardware-configuration.nix  # Gerado automaticamente (NÃO EDITAR)
```

## Arquivos-Chave

```
hosts/desktop/default.nix    # PC principal, NVIDIA, gaming
hosts/laptop/default.nix     # Notebook
hosts/wsl/default.nix        # WSL2 config
hosts/vm/default.nix         # VM para testes
```

## Padrão de Host

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

## Diferenças Entre Hosts

### Desktop vs Laptop

- **Desktop**: NVIDIA driver, Steam, GRUB com OS-Prober
- **Laptop**: Intel driver, systemd-boot padrão

### WSL vs Native

- **WSL**: Sem desktop, sem drivers gráficos, Docker Desktop
- **Native**: Desktop completo, drivers, home-manager GUI

## Como Adicionar Novo Host

1. Criar diretório `hosts/<novo>/`
2. Gerar hardware-config: `nixos-generate-config --show-hardware-config`
3. Criar `default.nix` seguindo o padrão
4. Adicionar em `flake.nix`:

```nix
nixosConfigurations = {
  novo = fnMountSystem { hostname = "novo"; };
};
```

## Comandos Úteis

```bash
# Rebuild host específico
sudo nixos-rebuild switch --flake .#desktop

# Dry-run (verificar sem aplicar)
sudo nixos-rebuild dry-run --flake .#laptop

# Build sem switch
sudo nixos-rebuild build --flake .#vm
```

## Variável isWsl

```nix
# Definida automaticamente no flake.nix
isWsl = true;  # Apenas para host wsl

# Usada em home/default.nix para imports condicionais
++ lib.optionals (!isWsl) [ ./features/programs ];
```
