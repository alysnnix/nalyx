---
paths:
  - "**/*.nix"
  - "flake.nix"
  - "flake.lock"
---

# Nix Coding Rules

## Estrutura de Módulos

### Padrão Básico

```nix
{ pkgs, vars, lib, config, ... }:
{
  imports = [ ];

  # Configurações aqui
}
```

### Com Condicionais

```nix
{ pkgs, vars, lib, ... }:
{
  imports = [
    ./base
  ] ++ (lib.optional (vars.desktop == "hyprland") ./hyprland)
    ++ (lib.optionals (!isWsl) [ ./gui-programs ]);
}
```

## Formatação

### Usar nixfmt

```bash
# Formatar arquivo específico
nix fmt path/to/file.nix

# Formatar todo o projeto
nix fmt
```

### Indentação

- 2 espaços
- Sem tabs

## Imports

### Ordem de Imports

1. Módulos locais obrigatórios
2. Hardware configuration
3. Módulos condicionais

```nix
imports = [
  # 1. Base obrigatória
  ./hardware-configuration.nix
  ../../modules/core

  # 2. Drivers
  ../../modules/drivers/nvidia.nix

  # 3. Condicionais
] ++ (lib.optional condition ./optional);
```

### Caminhos

- Usar caminhos relativos
- `./` para mesmo diretório
- `../` para subir níveis

## Pacotes

### Declaração

```nix
# Preferir with pkgs para listas
environment.systemPackages = with pkgs; [
  vim
  git
  curl
];

# Ou explícito para poucos pacotes
home.packages = [ pkgs.htop ];
```

### Overlays e Overrides

```nix
# Override com argumentos
(pkgs.google-chrome.override {
  commandLineArgs = [ "--flag" ];
})
```

## Home-Manager

### Estrutura

```nix
home = {
  username = vars.user.name;
  homeDirectory = "/home/${vars.user.name}";
  stateVersion = "25.11";  # Não mudar sem migração

  packages = with pkgs; [ ];
  sessionVariables = { };
};
```

### Programas

```nix
programs.nome = {
  enable = true;
  # configurações específicas
};
```

## Variáveis (vars.nix)

### Acessar Variáveis

```nix
# No módulo
{ vars, ... }:
{
  users.users.${vars.user.name} = { };
  programs.git.settings.user.email = vars.user.email;
}
```

### Adicionar Novas

```nix
# Em vars.nix
{
  user = {
    name = "aly";
    email = "email@example.com";
    newVar = "value";  # Nova variável
  };

  newTopLevel = "value";  # Nova variável top-level
}
```

## Secrets (SOPS)

### Declaração

```nix
sops = {
  defaultSopsFile = ../../secrets/secrets.yaml;
  defaultSopsFormat = "yaml";
  age.sshKeyPaths = [ "/home/${vars.user.name}/.ssh/id_ed25519" ];

  secrets.nome_secret.neededForUsers = true;
};
```

### Uso

```nix
# Referência ao arquivo descriptografado
config.sops.secrets.nome_secret.path
```

## Anti-Patterns

### Evitar

```nix
# ❌ Import de string
imports = [ "/absolute/path" ];

# ❌ with em escopo muito amplo
with pkgs; with lib; { }

# ❌ Hardcoded paths
home.file."/home/aly/.config" = { };

# ❌ Duplicação de código
# Extrair para módulo compartilhado

# ❌ Atributos repetidos (statix W:20)
# Atribuir a mesma key várias vezes causa warning
sops.secrets.password.neededForUsers = true;
sops.secrets.anytype_api_token.owner = vars.user.name;
sops.secrets.slack_bot_token.owner = vars.user.name;

# ✅ Agrupar num único bloco
sops.secrets = {
  password.neededForUsers = true;
  anytype_api_token.owner = vars.user.name;
  slack_bot_token.owner = vars.user.name;
};
```

### Preferir

```nix
# ✅ Import relativo
imports = [ ./relative/path ];

# ✅ with em escopo limitado
packages = with pkgs; [ vim git ];

# ✅ Variáveis
home.file."${config.home.homeDirectory}/.config" = { };

# ✅ Módulos reutilizáveis
imports = [ ../../shared/common.nix ];
```

## Flakes

### Estrutura do flake.nix

```nix
{
  description = "...";

  inputs = {
    nixpkgs.url = "...";
    # outros inputs
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = { };
    packages = { };
    devShells = { };
  };
}
```

### Atualizar Inputs

```bash
# Atualizar todos
nix flake update

# Atualizar específico
nix flake lock --update-input nixpkgs
```
