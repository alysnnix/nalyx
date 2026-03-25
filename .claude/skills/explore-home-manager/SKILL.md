---
name: explore-home-manager
description: "Explorar configurações Home-Manager. Use para debug de dotfiles, adicionar programas, ou configurar ferramentas de usuário."
user-invocable: true
---

# Home-Manager Configuration

## Overview

| Aspecto | Valor |
|---------|-------|
| Diretório | `home/` |
| Entry Point | `home/default.nix` |
| Features | `home/features/` |

## Estrutura

```
home/
├── default.nix           # Entry point, imports features
└── features/
    ├── cli/              # Ferramentas de linha de comando
    │   ├── zsh/          # Shell e scripts
    │   ├── git/          # Git config e signing
    │   ├── ssh/          # SSH keys e config
    │   ├── claude/       # Claude Code config
    │   └── gemini/       # Gemini config
    ├── desktop/          # Ambientes gráficos
    │   ├── hyprland/     # Hyprland + Waybar + Rofi + Matugen
    │   └── gnome/        # GNOME config
    ├── languages/        # Linguagens de programação
    │   ├── node/         # Node.js + npm
    │   ├── python/       # Python + pip
    │   ├── go/           # Go
    │   ├── java/         # Java JDK
    │   └── nix/          # Nix tools (nil, nixfmt)
    └── programs/         # Aplicativos GUI
        ├── firefox/      # Firefox config
        ├── vscode/       # VS Code + extensions
        ├── zed/          # Zed editor
        ├── docker/       # Docker tools
        ├── games/        # Gaming (não-Steam)
        └── obs/          # OBS Studio
```

## Arquivos-Chave

```
home/default.nix                    # Imports e packages base
home/features/cli/default.nix       # Imports CLI modules
home/features/cli/zsh/default.nix   # ZSH + Oh-My-Zsh
home/features/cli/git/default.nix   # Git config + signing
```

## Imports Condicionais

```nix
# Em home/default.nix
imports = [
  ./features/cli
  ./features/languages
]
++ (lib.optional (vars.desktop == "gnome") ./features/desktop/gnome)
++ (lib.optional (vars.desktop == "hyprland") ./features/desktop/hyprland)
++ lib.optionals (!isWsl) [ ./features/programs ];
```

## Padrão de Feature

```nix
# features/<categoria>/<nome>/default.nix
{ pkgs, vars, ... }:
{
  imports = [ ./submodule ];

  home.packages = with pkgs; [ pacote1 pacote2 ];

  programs.nome = {
    enable = true;
    # configurações
  };
}
```

## Como Adicionar Nova Feature

### 1. Criar Diretório

```bash
mkdir -p home/features/<categoria>/<nome>
```

### 2. Criar default.nix

```nix
{ pkgs, ... }:
{
  programs.nome = {
    enable = true;
  };
}
```

### 3. Importar no Módulo Pai

```nix
# home/features/<categoria>/default.nix
imports = [
  ./existente
  ./nome  # novo
];
```

## Packages Globais

```nix
# Em home/default.nix
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

## Scripts Customizados

```nix
# Em home/features/cli/zsh/default.nix
let
  myScripts = builtins.map (
    name: pkgs.writeShellScriptBin name (builtins.readFile ./scripts/${name}.sh)
  ) [ "update-sys" "szn-merge" ];
in
{
  home.packages = myScripts;
}
```

## Comandos Úteis

```bash
# Ver configuração home-manager
home-manager generations

# Rebuild apenas home-manager (se standalone)
home-manager switch --flake .#<user>@<host>
```
