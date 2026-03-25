---
name: explore-hyprland
description: "Explore Hyprland configuration. Use for desktop debugging, modifying keybinds, Waybar, Rofi, or Matugen themes."
user-invocable: true
---

# Hyprland Configuration

## Overview

| Aspect | Value |
|--------|-------|
| Directory | `home/features/desktop/hyprland/` |
| Entry Point | `home/features/desktop/hyprland/default.nix` |
| Condition | `vars.desktop == "hyprland"` |

## Structure

```
home/features/desktop/hyprland/
├── default.nix           # Main Hyprland module
├── hyprland.conf         # Hyprland configuration (keybinds, rules)
├── waybar/               # Status bar
│   ├── default.nix       # Waybar module
│   ├── config.jsonc      # Module configuration
│   └── style.css         # Styles
├── rofi/                 # Launcher
│   ├── default.nix       # Rofi module
│   ├── config.rasi       # Configuration
│   ├── style.rasi        # Styles
│   └── colors.rasi       # Colors
├── matugen/              # Material You theme generator
│   ├── default.nix       # Matugen module
│   └── templates/        # Color templates for apps
│       ├── hyprland-colors.conf
│       ├── waybar-colors.css
│       ├── rofi-colors.rasi
│       ├── kitty-colors.conf
│       ├── neovim/
│       └── ...
└── scripts/              # Helper scripts
```

## Key Files

```
hyprland.conf             # Keybinds, window rules, monitors
waybar/config.jsonc       # Bar modules
waybar/style.css          # Bar styles
rofi/config.rasi          # Launcher configuration
matugen/templates/        # Theme templates
```

## Configuration Flow

1. **hyprland.conf** defines keybinds and rules
2. **waybar** displays system information
3. **rofi** is the application launcher
4. **matugen** generates colors based on wallpaper

## Matugen (Material You Themes)

### What It Does

Generates a color palette from an image and applies it across all apps.

### Supported Templates

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

### Adding a New Template

1. Create a template in `matugen/templates/<app>.ext`
2. Use Matugen variables: `{{colors.primary}}`, `{{colors.surface}}`
3. Register in `matugen/default.nix`

## Common Keybinds

Defined in `hyprland.conf`:

```conf
# Default
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

## Waybar Modules

Defined in `waybar/config.jsonc`:

```json
{
  "modules-left": ["hyprland/workspaces"],
  "modules-center": ["clock"],
  "modules-right": ["network", "pulseaudio", "battery"]
}
```

## How to Modify

### Add a Keybind

Edit `hyprland.conf`:

```conf
bind = $mod SHIFT, S, exec, screenshot-script
```

### Add a Waybar Module

1. Edit `waybar/config.jsonc` - add module
2. Edit `waybar/style.css` - style it

### Change Theme

Run matugen with a new wallpaper image.
