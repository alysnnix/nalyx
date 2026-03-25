---
name: explore-hyprland
description: "Explorar configuração Hyprland. Use para debug de desktop, modificar keybinds, Waybar, Rofi, ou temas Matugen."
user-invocable: true
---

# Hyprland Configuration

## Overview

| Aspecto | Valor |
|---------|-------|
| Diretório | `home/features/desktop/hyprland/` |
| Entry Point | `home/features/desktop/hyprland/default.nix` |
| Condição | `vars.desktop == "hyprland"` |

## Estrutura

```
home/features/desktop/hyprland/
├── default.nix           # Módulo principal Hyprland
├── hyprland.conf         # Configuração Hyprland (keybinds, rules)
├── waybar/               # Barra de status
│   ├── default.nix       # Módulo Waybar
│   ├── config.jsonc      # Configuração módulos
│   └── style.css         # Estilos
├── rofi/                 # Launcher
│   ├── default.nix       # Módulo Rofi
│   ├── config.rasi       # Configuração
│   ├── style.rasi        # Estilos
│   └── colors.rasi       # Cores
├── matugen/              # Gerador de temas Material You
│   ├── default.nix       # Módulo Matugen
│   └── templates/        # Templates de cores para apps
│       ├── hyprland-colors.conf
│       ├── waybar-colors.css
│       ├── rofi-colors.rasi
│       ├── kitty-colors.conf
│       ├── neovim/
│       └── ...
└── scripts/              # Scripts auxiliares
```

## Arquivos-Chave

```
hyprland.conf             # Keybinds, window rules, monitors
waybar/config.jsonc       # Módulos da barra
waybar/style.css          # Estilos da barra
rofi/config.rasi          # Configuração do launcher
matugen/templates/        # Templates de temas
```

## Fluxo de Configuração

1. **hyprland.conf** define keybinds e regras
2. **waybar** mostra informações do sistema
3. **rofi** é o launcher de aplicativos
4. **matugen** gera cores baseado em wallpaper

## Matugen (Temas Material You)

### O Que Faz

Gera paleta de cores a partir de uma imagem e aplica em todos os apps.

### Templates Suportados

| App | Template |
|-----|----------|
| Hyprland | `hyprland-colors.conf` |
| Waybar | (via CSS) |
| Rofi | `rofi-colors.rasi` |
| Kitty | `kitty-colors.conf` |
| Alacritty | `alacritty.toml` |
| Neovim | `neovim/` |
| GTK | `gtk-colors.css` |
| Zed | `zed-colors.json` |
| Btop | `btop.theme` |
| Yazi | `yazi-theme.toml` |

### Adicionar Novo Template

1. Criar template em `matugen/templates/<app>.ext`
2. Usar variáveis Matugen: `{{colors.primary}}`, `{{colors.surface}}`
3. Registrar em `matugen/default.nix`

## Keybinds Comuns

Definidos em `hyprland.conf`:

```conf
# Padrão
$mod = SUPER
bind = $mod, Return, exec, kitty
bind = $mod, D, exec, rofi -show drun
bind = $mod, Q, killactive
```

## Window Rules

```conf
windowrulev2 = float, class:^(pavucontrol)$
windowrulev2 = workspace 2, class:^(firefox)$
```

## Waybar Módulos

Definidos em `waybar/config.jsonc`:

```json
{
  "modules-left": ["hyprland/workspaces"],
  "modules-center": ["clock"],
  "modules-right": ["network", "pulseaudio", "battery"]
}
```

## Como Modificar

### Adicionar Keybind

Editar `hyprland.conf`:

```conf
bind = $mod SHIFT, S, exec, screenshot-script
```

### Adicionar Módulo Waybar

1. Editar `waybar/config.jsonc` - adicionar módulo
2. Editar `waybar/style.css` - estilizar

### Mudar Tema

Executar matugen com nova imagem de wallpaper.
