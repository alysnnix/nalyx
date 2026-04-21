# Nalyx

Personal NixOS configuration with public/private split for multi-host support.

## Quick Start

```bash
switch           # Build system (auto-detects hostname)
switch wsl       # Specify a host
nix flake check --no-build  # Validate
nix fmt          # Format code
nix develop      # Enter devShell (installs pre-commit hooks)
```

## Critical Rules

- NEVER edit `hardware-configuration.nix` files manually — they are auto-generated
- NEVER edit `~/.claude/CLAUDE.md` directly — it is managed via Nix at `home/features/cli/claude/global-claude-md.md`
- ALWAYS validate with `nix flake check --no-build` before commit
- NEVER put personal data in the public repo — use nalyx-private for secrets and real values

## Public / Private Architecture

The repo has an optional private companion (`nalyx-private`) cloned into `.private/` (gitignored). Detection uses `private ? null` in `flake.nix`:

- **Without private repo**: safe defaults, `initialPassword = "changeme"`, SOPS disabled
- **With private repo**: conditionally includes `privateNixosModules` and `privateHmModules`

Private modules are only referenced in `flake.nix` — no public module knows the private repo exists.

## Stack

| Layer | Technologies |
|-------|-------------|
| System | NixOS, Flakes, Home-Manager |
| Desktop | Hyprland (Caelestia/Waybar), GNOME |
| Theming | Matugen (dynamic color generation) |
| Secrets | SOPS-nix, Age |
| Boot | systemd-boot (Lanzaboote optional) |
| Shell | Zsh |
| Drivers | NVIDIA, Intel |
| AI Tools | Claude Code, Gemini CLI, OpenCode |
| Services | Tailscale, Syncthing, NordVPN, OpenClaw |

## Hosts

| Host | Description | Desktop | Extras |
|------|-------------|---------|--------|
| `desktop` | Main PC | Hyprland/GNOME | NVIDIA, Steam, Gaming |
| `laptop` | Notebook | Hyprland/GNOME | Intel, KDE Connect |
| `wsl` | WSL2 | None | Docker, Pritunl, Playwright |
| `vm` | Test VM | Hyprland/GNOME | QEMU, Waydroid |
| `homelab` | Server | None | Tailscale, Syncthing, OpenClaw |

There is also a standalone `homeConfigurations.wsl-ubuntu` for Ubuntu WSL without NixOS.

## Project Structure

```
hosts/           # NixOS system configs per host
modules/
  core/          # Base system (all hosts)
  desktop/       # Hyprland, GNOME (system-level)
  drivers/       # NVIDIA, Intel
  services/      # NordVPN, Syncthing, OpenClaw
  secureboot/    # Lanzaboote (optional)
home/
  default.nix    # Root HM config
  features/
    cli/         # zsh, git, ssh, neovim, claude, gemini, opencode
    desktop/     # hyprland (caelestia/waybar/rofi/matugen), gnome
    languages/   # go, java, latex, nix, node, python
    programs/    # docker, firefox, games, obs, vscode, zed
generators/      # ISO generation for installation
packages/        # Custom Nix packages
ci/              # CI scaffolding (empty-private placeholder)
scripts/         # Utility scripts (homelab-install)
```

## Code Conventions

- Module pattern: `{ pkgs, vars, lib, config, ... }:`
- Conditional imports: `lib.optional (vars.desktop == "hyprland") ./hyprland`
- HM special args: `isWsl`, `isServer`, `enableClaude`, `enableGemini`, `enableOpencode`
- Directories: `kebab-case`, main files: `default.nix`
- Host helper: `fnMountSystem` in `flake.nix` builds each host config

## Key Variables (`vars.nix`)

- `vars.user.name`, `vars.user.email`, `vars.user.publicKey`
- `vars.desktop` — `"hyprland"`, `"gnome"`, or `null` (headless)
- `vars.shell` — `"caelestia"` or `"waybar"` (Hyprland shell choice)
- `vars.terminal`, `vars.editor`
- `vars.homelab.address`

## Pre-commit Hooks

`nixfmt`, `statix`, `deadnix` — activated automatically with `nix develop`.

## Git

- ALWAYS add `Co-Authored-By: Claude <noreply@anthropic.com>` to ALL commit messages

### Commit Format

```
type(scope): short description    ← max 50 chars total

- bullet explaining what changed
- another bullet if needed

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Commit Rules

- Title: `type(scope): message` — **50 characters max** including type and scope
- Scope: module, feature, or area affected
- Body: lowercase, short bullet points — concise but complete
- Lowercase, no period, imperative mood

## Quality Rules

@.claude/rules/quality.md

## Additional Rules

@.claude/rules/nix.md
