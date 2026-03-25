---
paths:
  - "**/*.nix"
  - "flake.nix"
  - "flake.lock"
---

# Nix Coding Rules

## Module Structure

### Basic Pattern

```nix
{ pkgs, vars, lib, config, ... }:
{
  imports = [ ];

  # Configurations here
}
```

### With Conditionals

```nix
{ pkgs, vars, lib, ... }:
{
  imports = [
    ./base
  ] ++ (lib.optional (vars.desktop == "hyprland") ./hyprland)
    ++ (lib.optionals (!isWsl) [ ./gui-programs ]);
}
```

## Formatting

### Use nixfmt

```bash
# Format a specific file
nix fmt path/to/file.nix

# Format the entire project
nix fmt
```

### Indentation

- 2 spaces
- No tabs

## Imports

### Import Order

1. Required local modules
2. Hardware configuration
3. Conditional modules

```nix
imports = [
  # 1. Required base
  ./hardware-configuration.nix
  ../../modules/core

  # 2. Drivers
  ../../modules/drivers/nvidia.nix

  # 3. Conditionals
] ++ (lib.optional condition ./optional);
```

### Paths

- Use relative paths
- `./` for the same directory
- `../` to go up levels

## Packages

### Declaration

```nix
# Prefer with pkgs for lists
environment.systemPackages = with pkgs; [
  vim
  git
  curl
];

# Or explicit for few packages
home.packages = [ pkgs.htop ];
```

### Overlays and Overrides

```nix
# Override with arguments
(pkgs.google-chrome.override {
  commandLineArgs = [ "--flag" ];
})
```

## Home-Manager

### Structure

```nix
home = {
  username = vars.user.name;
  homeDirectory = "/home/${vars.user.name}";
  stateVersion = "25.11";  # Do not change without migration

  packages = with pkgs; [ ];
  sessionVariables = { };
};
```

### Programs

```nix
programs.name = {
  enable = true;
  # specific configurations
};
```

## Variables (vars.nix)

### Accessing Variables

```nix
# In the module
{ vars, ... }:
{
  users.users.${vars.user.name} = { };
  programs.git.settings.user.email = vars.user.email;
}
```

### Adding New Variables

```nix
# In vars.nix
{
  user = {
    name = "aly";
    email = "email@example.com";
    newVar = "value";  # New variable
  };

  newTopLevel = "value";  # New top-level variable
}
```

## Secrets (SOPS)

### Declaration

```nix
sops = {
  defaultSopsFile = ../../secrets/secrets.yaml;
  defaultSopsFormat = "yaml";
  age.sshKeyPaths = [ "/home/${vars.user.name}/.ssh/id_ed25519" ];

  secrets.secret_name.neededForUsers = true;
};
```

### Usage

```nix
# Reference to the decrypted file
config.sops.secrets.secret_name.path
```

## Anti-Patterns

### Avoid

```nix
# ❌ String import
imports = [ "/absolute/path" ];

# ❌ with in overly broad scope
with pkgs; with lib; { }

# ❌ Hardcoded paths
home.file."/home/aly/.config" = { };

# ❌ Code duplication
# Extract to a shared module

# ❌ Repeated attributes (statix W:20)
# Assigning the same key multiple times causes a warning
sops.secrets.password.neededForUsers = true;
sops.secrets.anytype_api_token.owner = vars.user.name;
sops.secrets.slack_bot_token.owner = vars.user.name;

# ✅ Group into a single block
sops.secrets = {
  password.neededForUsers = true;
  anytype_api_token.owner = vars.user.name;
  slack_bot_token.owner = vars.user.name;
};
```

### Prefer

```nix
# ✅ Relative import
imports = [ ./relative/path ];

# ✅ with in limited scope
packages = with pkgs; [ vim git ];

# ✅ Variables
home.file."${config.home.homeDirectory}/.config" = { };

# ✅ Reusable modules
imports = [ ../../shared/common.nix ];
```

## Flakes

### flake.nix Structure

```nix
{
  description = "...";

  inputs = {
    nixpkgs.url = "...";
    # other inputs
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = { };
    packages = { };
    devShells = { };
  };
}
```

### Updating Inputs

```bash
# Update all
nix flake update

# Update a specific one
nix flake lock --update-input nixpkgs
```
