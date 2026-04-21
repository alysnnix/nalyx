# Private Flake Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform nalyx-private from a raw path input into a proper flake that exports NixOS and Home-Manager modules, eliminating `hasPrivate` from all public modules.

**Architecture:** nalyx-private becomes a flake exporting `nixosModules` and `homeManagerModules`. The public nalyx flake conditionally imports them in one place (`flake.nix`). All public modules become simpler — no `hasPrivate`, no `private` arg, no conditional SOPS logic. The private modules overlay config on top of public defaults using `mkForce`/`mkDefault`.

**Tech Stack:** NixOS, Flakes, Home-Manager, SOPS-nix

---

## File Structure

### nalyx (public) — files to modify

- `flake.nix` — change private input to optional flake, single conditional import
- `vars.nix` — real non-sensitive values (email, public key URL)
- `modules/core/default.nix` — remove SOPS block, remove hasPrivate
- `hosts/wsl/default.nix` — remove SOPS block, remove hasPrivate, use initialPassword
- `hosts/homelab/default.nix` — remove hasPrivate conditionals
- `modules/services/openclaw.nix` — remove hasPrivate conditionals, use defaults
- `home/features/cli/default.nix` — remove hasPrivate, remove private wrk import
- `home/features/cli/zsh/default.nix` — remove hasPrivate, remove private scripts
- `home/features/cli/claude/default.nix` — remove hasPrivate/private args
- `home/features/cli/claude/settings/default.nix` — remove hasPrivate/private args
- `home/features/cli/claude/settings/mcp-servers.nix` — remove private MCP logic
- `home/features/cli/claude/activation/settings.nix` — remove private MCP inject
- `home/features/cli/opencode/default.nix` — remove hasPrivate/private args
- `home/features/cli/opencode/settings/default.nix` — remove hasPrivate/private args
- `home/features/cli/opencode/settings/mcp-servers.nix` — remove private MCP logic
- `home/features/cli/opencode/activation/settings.nix` — remove private MCP inject
- `generators/default.nix` — remove hasPrivate/private passthrough

### nalyx-private — files to create/modify

- `flake.nix` — new, exports nixosModules + homeManagerModules
- `nixos/default.nix` — new, SOPS config + secrets declarations
- `nixos/sops-wsl.nix` — new, WSL-specific secrets (minimax, openrouter, litellm)
- `nixos/sops-core.nix` — new, shared secrets (password, slack, sapron, etc)
- `nixos/openclaw.nix` — new, openclaw SOPS template + minimax key
- `nixos/homelab.nix` — new, wifi + environment files
- `home/default.nix` — new, HM module entry point
- `home/claude-mcps.nix` — new, private MCPs for claude (sapron, datalake, etc)
- `home/opencode-mcps.nix` — new, private MCPs for opencode (if needed)
- `home/zsh.nix` — new, private scripts + aliases (szn, secrets, etc)
- `home/wrk.nix` — move existing wrk.nix here
- `secrets/secrets.yaml` — unchanged
- `.sops.yaml` — unchanged

### nalyx (public) — files to delete

- `private/default.nix` — empty placeholder no longer needed

---

### Task 1: Create nalyx-private flake.nix

**Files:**
- Create: `nalyx-private/flake.nix`

- [ ] **Step 1: Write the flake.nix**

```nix
{
  description = "Nalyx private configuration — SOPS secrets, private modules, work configs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosModules = {
      default = import ./nixos;
      openclaw = import ./nixos/openclaw.nix;
      homelab = import ./nixos/homelab.nix;
    };

    homeManagerModules = {
      default = import ./home;
    };
  };
}
```

- [ ] **Step 2: Commit**

```bash
git add flake.nix
git commit -m "feat: add flake.nix with module exports"
```

---

### Task 2: Create private NixOS modules (SOPS + secrets)

**Files:**
- Create: `nalyx-private/nixos/default.nix`
- Create: `nalyx-private/nixos/sops-core.nix`
- Create: `nalyx-private/nixos/sops-wsl.nix`
- Create: `nalyx-private/nixos/openclaw.nix`
- Create: `nalyx-private/nixos/homelab.nix`

- [ ] **Step 1: Create nixos/default.nix (entry point)**

```nix
{ vars, config, lib, ... }:
{
  imports = [ ./sops-core.nix ];

  users.users.${vars.user.name} = {
    hashedPasswordFile = lib.mkForce config.sops.secrets.password.path;
  };

  services.tailscale.authKeyFile = lib.mkForce config.sops.secrets.tailscale_auth_key.path;
}
```

- [ ] **Step 2: Create nixos/sops-core.nix (shared secrets)**

```nix
{ vars, ... }:
{
  sops = {
    defaultSopsFile = "${./../secrets/secrets.yaml}";
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/home/${vars.user.name}/.ssh/id_ed25519" ];
    secrets = {
      password.neededForUsers = true;
      slack_bot_token.owner = vars.user.name;
      sapron_cf_client_id.owner = vars.user.name;
      sapron_cf_client_secret.owner = vars.user.name;
      seazone_mcp_api_key.owner = vars.user.name;
      coolify_api_key.owner = vars.user.name;
      grafana_api_key.owner = vars.user.name;
      tailscale_auth_key = { };
    };
  };
}
```

- [ ] **Step 3: Create nixos/sops-wsl.nix (WSL-only secrets)**

```nix
{ vars, ... }:
{
  sops.secrets = {
    minimax_api_key.owner = vars.user.name;
    openrouter_api_key.owner = vars.user.name;
    litellm_api_key.owner = vars.user.name;
  };
}
```

- [ ] **Step 4: Create nixos/openclaw.nix (openclaw SOPS)**

Move the SOPS-specific config from `modules/services/openclaw.nix` — the `sops.secrets.openclaw_minimax_key`, `sops.templates`, and the conditional systemd tmpfiles content. The public openclaw module will use `mkDefault` for the `.env` fallback.

```nix
{ config, lib, ... }:
let
  dataDir = "/var/lib/openclaw";
in
{
  sops.secrets.openclaw_minimax_key = { };

  sops.templates."openclaw-env" = {
    content = ''
      MINIMAX_API_KEY=${config.sops.placeholder.openclaw_minimax_key}
    '';
  };

  systemd.tmpfiles.rules = lib.mkForce [
    "d ${dataDir} 0755 1000 1000 -"
    "d ${dataDir}/config 0755 1000 1000 -"
    "d ${dataDir}/data 0755 1000 1000 -"
  ];

  virtualisation.oci-containers.containers.openclaw.environmentFiles = [
    config.sops.templates."openclaw-env".path
  ];
}
```

- [ ] **Step 5: Create nixos/homelab.nix (wifi + env files)**

Move the `hasPrivate` conditionals from `hosts/homelab/default.nix`:

```nix
{ config, lib, ... }:
{
  sops.secrets.wifi_password = { };

  sops.templates."wifi-env" = {
    content = ''
      WIFI_PASSWORD=${config.sops.placeholder.wifi_password}
    '';
  };

  networking.wireless.environmentFiles = [
    config.sops.templates."wifi-env".path
  ];
}
```

- [ ] **Step 6: Commit**

```bash
git add nixos/
git commit -m "feat: add nixos modules for SOPS and secrets"
```

---

### Task 3: Create private Home-Manager modules

**Files:**
- Create: `nalyx-private/home/default.nix`
- Create: `nalyx-private/home/claude-mcps.nix`
- Create: `nalyx-private/home/zsh.nix`
- Move: existing `home/features/cli/wrk.nix` stays as-is

- [ ] **Step 1: Create home/default.nix (entry point)**

```nix
{ pkgs, lib, ... }:
{
  imports = [
    ./claude-mcps.nix
    ./zsh.nix
    ./wrk.nix
  ];
}
```

- [ ] **Step 2: Create home/claude-mcps.nix**

This module needs to inject private MCPs into claude and opencode settings. Since the activation scripts read `/run/secrets/*` at runtime, this module just needs to ensure the MCP definitions and injection scripts are available.

The approach: use `home.activation` to extend the existing settings with private MCPs. The private module adds an activation script that runs AFTER the public `claudeSettings` activation.

```nix
{ pkgs, lib, ... }:
let
  jq = "${pkgs.jq}/bin/jq";
in
{
  home.activation.claudePrivateMcps = lib.hm.dag.entryAfter [ "claudeSettings" ] ''
    JQ="${jq}"
    SETTINGS_FILE="$HOME/.claude/settings.json"
    SAPRON_ID_SECRET="/run/secrets/sapron_cf_client_id"
    SAPRON_SECRET_SECRET="/run/secrets/sapron_cf_client_secret"
    SEAZONE_MCP_KEY_SECRET="/run/secrets/seazone_mcp_api_key"
    GRAFANA_SECRET="/run/secrets/grafana_api_key"

    if [ -f "$SETTINGS_FILE" ]; then
      CURRENT=$(cat "$SETTINGS_FILE")

      # Inject Sapron MCP
      if [ -f "$SAPRON_ID_SECRET" ] && [ -f "$SAPRON_SECRET_SECRET" ]; then
        CF_ID=$(cat "$SAPRON_ID_SECRET")
        CF_SECRET=$(cat "$SAPRON_SECRET_SECRET")
        CURRENT=$(echo "$CURRENT" | $JQ \
          --arg id "CF-Access-Client-Id:$CF_ID" \
          --arg secret "CF-Access-Client-Secret:$CF_SECRET" \
          '.mcpServers.sapron = {
            "command": "npx",
            "args": ["mcp-remote", "https://mcp.sapron.com.br/mcp", "--header", $id, "--header", $secret]
          }')
      fi

      # Inject Seazone MCPs (sirius-precificacao + datalake)
      if [ -f "$SEAZONE_MCP_KEY_SECRET" ]; then
        SZ_KEY=$(cat "$SEAZONE_MCP_KEY_SECRET")
        CURRENT=$(echo "$CURRENT" | $JQ --arg key "$SZ_KEY" '
          .mcpServers."sirius-precificacao" = {
            "type": "http",
            "url": "https://g7hxu8yujb.execute-api.us-west-2.amazonaws.com/v1/mcp",
            "headers": {"x-api-key": $key}
          } |
          .mcpServers.datalake = {
            "type": "http",
            "url": "https://ln8gpsqb36.execute-api.us-west-2.amazonaws.com/mcp",
            "headers": {"x-api-key": $key}
          }')
      fi

      # Inject Grafana MCP
      if [ -f "$GRAFANA_SECRET" ]; then
        GRAFANA_TOKEN=$(cat "$GRAFANA_SECRET")
        CURRENT=$(echo "$CURRENT" | $JQ --arg token "$GRAFANA_TOKEN" '
          .mcpServers.grafana = {
            "command": "uvx",
            "args": ["mcp-grafana"],
            "env": {
              "GRAFANA_URL": "https://monitoring.seazone.com.br",
              "GRAFANA_SERVICE_ACCOUNT_TOKEN": $token
            }
          }')
      fi

      echo "$CURRENT" > "$SETTINGS_FILE"
    fi
  '';

  # Same pattern for opencode if needed in future
}
```

- [ ] **Step 3: Create home/zsh.nix (private scripts + aliases)**

```nix
{ pkgs, ... }:
let
  privateScripts = map
    (name: pkgs.writeShellScriptBin name (builtins.readFile "${./../scripts}/${name}.sh"))
    [ "szn-merge-pr" "szn-merge" "szn-ssm" ];
in
{
  home.packages = privateScripts;

  programs.zsh.shellAliases = {
    secrets = ''EDITOR="code --wait" nix-shell -p sops --run "sops ~/nalyx/.private/nalyx-private/secrets/secrets.yaml"'';
    szn = "cd ~/wrk/seazone-tech";
  };
}
```

- [ ] **Step 4: Commit**

```bash
git add home/
git commit -m "feat: add home-manager modules for MCPs and scripts"
```

---

### Task 4: Update nalyx vars.nix with real values

**Files:**
- Modify: `nalyx/vars.nix`

- [ ] **Step 1: Update vars.nix**

```nix
{
  user = {
    name = "aly";
    email = "4ly.alcantara@gmail.com";
    publicKeyUrl = "https://github.com/alysnnix.keys";

    social = {
      github = "alysnnix";
    };
  };

  terminal = "kitty";
  editor = "nvim";
  desktop = "hyprland";
  shell = "caelestia";

  homelab = {
    address = "homelab.local";
  };

  weather = {
    location = "";
  };
}
```

Note: `publicKey` is replaced by `publicKeyUrl`. Any module that used `vars.user.publicKey` needs to be updated to fetch the key from the URL or use the new field name. Check which modules reference `publicKey` and update them.

- [ ] **Step 2: Commit**

```bash
git add vars.nix
git commit -m "refactor: use real values in vars.nix"
```

---

### Task 5: Clean flake.nix — single conditional

**Files:**
- Modify: `nalyx/flake.nix`
- Delete: `nalyx/private/default.nix`

- [ ] **Step 1: Update the private input**

Change from path-based to optional flake:

```nix
# Remove:
private = {
  url = "path:./private";
  flake = false;
};

# Replace with:
# Private repo is optional — override with:
#   nix flake lock --override-input private git+ssh://git@github.com/alysnnix/nalyx-private
private = {
  url = "github:alysnnix/nalyx-private";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note: for users without access, they override with an empty flake or remove the input entirely. The `follows` ensures nixpkgs is shared.

- [ ] **Step 2: Remove hasPrivate logic, use optional module import**

Replace the `hasPrivate` detection and `vars` merge with:

```nix
outputs = { self, nixpkgs, home-manager, ..., private ? null, ... }@inputs:
let
  # No more vars merging — vars.nix has real values
  vars = import ./vars.nix;

  # Private modules (empty list if private repo unavailable)
  privateNixosModules =
    if private != null && (private ? nixosModules)
    then [ private.nixosModules.default ]
    else [ ];

  privateHmModules =
    if private != null && (private ? homeManagerModules)
    then [ private.homeManagerModules.default ]
    else [ ];
```

- [ ] **Step 3: Update fnMountSystem**

Remove `hasPrivate` and `private` from specialArgs. Add private modules to the module list:

```nix
fnMountSystem = { hostname, extraModules ? [], ... }:
  nixpkgs.lib.nixosSystem {
    specialArgs = {
      inherit inputs vars;
      # No more hasPrivate or private here
    };
    modules = [
      ./hosts/${hostname}/default.nix
      sops-nix.nixosModules.sops
      home-manager.nixosModules.home-manager
      { ... home-manager config with privateHmModules in sharedModules ... }
    ]
    ++ privateNixosModules
    ++ extraModules;
  };
```

For WSL, also add `private.nixosModules.sops-wsl` if available. For homelab, add `private.nixosModules.homelab`. For openclaw hosts, add `private.nixosModules.openclaw`.

- [ ] **Step 4: Remove private/default.nix placeholder**

```bash
rm -rf private/
```

- [ ] **Step 5: Commit**

```bash
git add flake.nix
git rm -r private/
git commit -m "refactor: private as optional flake input"
```

---

### Task 6: Clean modules/core/default.nix

**Files:**
- Modify: `nalyx/modules/core/default.nix`

- [ ] **Step 1: Remove hasPrivate and SOPS block**

Remove from function args: `hasPrivate ? false, private ? null`

Remove the entire `sops = lib.mkIf hasPrivate { ... }` block.

Change tailscale to not reference SOPS:
```nix
services.tailscale = {
  enable = true;
  # authKeyFile set by private module when available
};
```

Change user password to safe default:
```nix
users.users.${vars.user.name} = {
  isNormalUser = true;
  # ...
  initialPassword = lib.mkDefault "changeme";
  # Private module overrides with hashedPasswordFile via mkForce
};
```

- [ ] **Step 2: Commit**

```bash
git add modules/core/default.nix
git commit -m "refactor(core): remove hasPrivate and SOPS"
```

---

### Task 7: Clean hosts/wsl/default.nix

**Files:**
- Modify: `nalyx/hosts/wsl/default.nix`

- [ ] **Step 1: Remove hasPrivate and SOPS**

Remove from args: `hasPrivate ? false, private ? null`

Remove entire `sops = lib.mkIf hasPrivate { ... }` block.

Replace user password conditional:
```nix
users.users.${vars.user.name} = {
  isNormalUser = true;
  extraGroups = [ "wheel" "networkmanager" "docker" ];
  shell = pkgs.zsh;
  initialPassword = lib.mkDefault "changeme";
};
```

- [ ] **Step 2: Commit**

```bash
git add hosts/wsl/default.nix
git commit -m "refactor(wsl): remove hasPrivate and SOPS"
```

---

### Task 8: Clean hosts/homelab/default.nix

**Files:**
- Modify: `nalyx/hosts/homelab/default.nix`

- [ ] **Step 1: Remove hasPrivate conditionals**

Remove from args: `hasPrivate ? false`

Replace `lib.mkIf hasPrivate` blocks with `lib.mkDefault` values or remove them entirely (the private homelab module will set these).

- [ ] **Step 2: Commit**

```bash
git add hosts/homelab/default.nix
git commit -m "refactor(homelab): remove hasPrivate"
```

---

### Task 9: Clean modules/services/openclaw.nix

**Files:**
- Modify: `nalyx/modules/services/openclaw.nix`

- [ ] **Step 1: Remove hasPrivate conditionals**

Remove from args: `hasPrivate ? false, private ? null`

Remove SOPS block. Replace conditional `.env` logic with a default:
```nix
# Default .env created by tmpfiles; private module injects real key via SOPS template
systemd.tmpfiles.rules = [
  "d ${dataDir} 0755 1000 1000 -"
  "d ${dataDir}/config 0755 1000 1000 -"
  "d ${dataDir}/data 0755 1000 1000 -"
  "f ${dataDir}/.env 0640 1000 1000 -"
];
```

- [ ] **Step 2: Commit**

```bash
git add modules/services/openclaw.nix
git commit -m "refactor(openclaw): remove hasPrivate"
```

---

### Task 10: Clean home/features/cli/ modules

**Files:**
- Modify: `nalyx/home/features/cli/default.nix`
- Modify: `nalyx/home/features/cli/zsh/default.nix`
- Modify: `nalyx/home/features/cli/claude/default.nix`
- Modify: `nalyx/home/features/cli/claude/settings/default.nix`
- Modify: `nalyx/home/features/cli/claude/settings/mcp-servers.nix`
- Modify: `nalyx/home/features/cli/claude/activation/settings.nix`
- Modify: `nalyx/home/features/cli/opencode/default.nix`
- Modify: `nalyx/home/features/cli/opencode/settings/default.nix`
- Modify: `nalyx/home/features/cli/opencode/settings/mcp-servers.nix`
- Modify: `nalyx/home/features/cli/opencode/activation/settings.nix`

- [ ] **Step 1: Clean cli/default.nix**

Remove `hasPrivate ? false, private ? null` from args.
Remove `++ (lib.optional hasPrivate "${private}/home/features/cli/wrk.nix")`.

- [ ] **Step 2: Clean cli/zsh/default.nix**

Remove `hasPrivate ? false, private ? null` from args.
Remove `privateScripts` logic entirely.
Remove `secrets` and `szn` aliases (moved to private module).

- [ ] **Step 3: Clean claude modules**

Remove `hasPrivate ? false, private ? null` from:
- `claude/default.nix`
- `claude/settings/default.nix`

Simplify `claude/settings/mcp-servers.nix` — remove `privateMcpConfig` logic:
```nix
{
  publicMcpServers = {
    slack = { ... };
  };
}
```

Simplify `claude/activation/settings.nix` — remove `${privateMcpConfig.injectScript}` line. The private HM module runs its own activation AFTER this one.

- [ ] **Step 4: Clean opencode modules**

Same pattern as claude — remove `hasPrivate/private` from all opencode files.
Simplify `mcp-servers.nix` and `activation/settings.nix`.

- [ ] **Step 5: Commit**

```bash
git add home/features/cli/
git commit -m "refactor(cli): remove hasPrivate from all modules"
```

---

### Task 11: Clean generators/default.nix

**Files:**
- Modify: `nalyx/generators/default.nix`

- [ ] **Step 1: Remove hasPrivate/private passthrough**

Remove these from function args and from any inner calls.

- [ ] **Step 2: Commit**

```bash
git add generators/default.nix
git commit -m "refactor(generators): remove hasPrivate"
```

---

### Task 12: Delete nalyx-private/vars-override.nix

**Files:**
- Delete: `nalyx-private/vars-override.nix`

- [ ] **Step 1: Remove the file**

No longer needed — real values live in nalyx/vars.nix.

```bash
rm vars-override.nix
git add -A
git commit -m "cleanup: remove vars-override.nix"
```

---

### Task 13: Validate everything

- [ ] **Step 1: Validate nalyx without private**

Temporarily override the private input to test standalone:
```bash
nix flake check --no-build --override-input private path:./private-empty
```

Or simply remove the private input temporarily and run:
```bash
nix flake check --no-build
```

Expected: all hosts build without errors using default values.

- [ ] **Step 2: Validate nalyx with private**

```bash
nix flake lock --override-input private path:./.private/nalyx-private
nix flake check --no-build
```

Expected: all hosts build with SOPS and private modules active.

- [ ] **Step 3: Test actual rebuild on WSL**

```bash
switch
```

Verify: SOPS secrets decrypted, MCPs injected, private scripts available.

- [ ] **Step 4: Commit any fixes and final cleanup**

```bash
git add -A
git commit -m "fix: migration adjustments"
```
