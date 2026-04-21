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

The repo has an optional private companion (`nalyx-private`) cloned into `.private/` (gitignored). Detection uses `hasPrivate`:

- **Without private repo**: safe defaults, `initialPassword = "changeme"`, SOPS disabled
- **With private repo**: merges real values via `recursiveUpdate`, enables SOPS secrets

Modules receive `hasPrivate` and `private` via specialArgs to conditionally enable private features.

## Stack

| Layer | Technologies |
|-------|-------------|
| System | NixOS, Flakes, Home-Manager |
| Desktop | Hyprland, GNOME |
| Secrets | SOPS-nix, Age |
| Boot | Lanzaboote (Secure Boot), systemd-boot |
| Shell | Zsh, Oh-My-Zsh |
| Drivers | NVIDIA, Intel |

## Hosts

| Host | Description | Desktop | Extras |
|------|-------------|---------|--------|
| `desktop` | Main PC | Hyprland/GNOME | NVIDIA, Steam, Gaming |
| `laptop` | Notebook | Hyprland/GNOME | Intel |
| `wsl` | WSL2 | None | Docker Desktop |
| `vm` | Test VM | Hyprland/GNOME | Minimal |
| `homelab` | Server | None | Tailscale-only, headless |

## Code Conventions

- Module pattern: `{ pkgs, vars, lib, hasPrivate ? false, private ? null, ... }:`
- Conditional imports: `lib.optional (vars.desktop == "hyprland") ./hyprland`
- Directories: `kebab-case`, main files: `default.nix`

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
