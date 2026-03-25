---
name: explore-home-manager
description: "Explore Home-Manager configurations. Use for dotfile debugging, adding programs, or configuring user tools."
user-invocable: true
---

# Home-Manager Configuration

## Overview

| Aspect | Value |
|--------|-------|
| Directory | `home/` |
| Entry Point | `home/default.nix` |
| Features | `home/features/` |

## Structure

```
home/
├── default.nix           # Entry point, imports features
└── features/
    ├── cli/              # Command-line tools
    │   ├── zsh/          # Shell and scripts
    │   ├── git/          # Git config and signing
    │   ├── ssh/          # SSH keys and config
    │   ├── claude/       # Claude Code config
    │   └── gemini/       # Gemini config
    ├── desktop/          # Graphical environments
    │   ├── hyprland/     # Hyprland + Waybar + Rofi + Matugen
    │   └── gnome/        # GNOME config
    ├── languages/        # Programming languages
    │   ├── node/         # Node.js + npm
    │   ├── python/       # Python + pip
    │   ├── go/           # Go
    │   ├── java/         # Java JDK
    │   └── nix/          # Nix tools (nil, nixfmt)
    └── programs/         # GUI applications
        ├── firefox/      # Firefox config
        ├── vscode/       # VS Code + extensions
        ├── zed/          # Zed editor
        ├── docker/       # Docker tools
        ├── games/        # Gaming (non-Steam)
        └── obs/          # OBS Studio
```

## Key Files

```
home/default.nix                    # Imports and base packages
home/features/cli/default.nix       # CLI module imports
home/features/cli/zsh/default.nix   # ZSH + Oh-My-Zsh
home/features/cli/git/default.nix   # Git config + signing
```

## Conditional Imports

```nix
# In home/default.nix
imports = [
  ./features/cli
  ./features/languages
]
++ (lib.optional (vars.desktop == "gnome") ./features/desktop/gnome)
++ (lib.optional (vars.desktop == "hyprland") ./features/desktop/hyprland)
++ lib.optionals (!isWsl) [ ./features/programs ];
```

## Feature Pattern

```nix
# features/<category>/<name>/default.nix
{ pkgs, vars, ... }:
{
  imports = [ ./submodule ];

  home.packages = with pkgs; [ package1 package2 ];

  programs.name = {
    enable = true;
    # configurations
  };
}
```

## How to Add a New Feature

### 1. Create Directory

```bash
mkdir -p home/features/<category>/<name>
```

### 2. Create default.nix

```nix
{ pkgs, ... }:
{
  programs.name = {
    enable = true;
  };
}
```

### 3. Import in the Parent Module

```nix
# home/features/<category>/default.nix
imports = [
  ./existing
  ./name  # new
];
```

## Global Packages

```nix
# In home/default.nix
home.packages = with pkgs; [
  spotify
  slack
  gh
  google-chrome
];
```

## Session Variables

```nix
home.sessionVariables = {
  EDITOR = "vim";
  BROWSER = "firefox";
};
```

## Custom Scripts

```nix
# In home/features/cli/zsh/default.nix
let
  myScripts = builtins.map (
    name: pkgs.writeShellScriptBin name (builtins.readFile ./scripts/${name}.sh)
  ) [ "update-sys" "szn-merge" ];
in
{
  home.packages = myScripts;
}
```

## Useful Commands

```bash
# View home-manager configuration
home-manager generations

# Rebuild home-manager only (if standalone)
home-manager switch --flake .#<user>@<host>
```
