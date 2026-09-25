# Nalyx

Personal NixOS configuration. Public, employer-neutral, with pluggable private layers.

## Quick Start

```bash
switch           # Build system (switches to main, auto-detects hostname)
switch wsl       # Specify a host
switch <job>     # The wrk profile with the .private/nix-priv-<job> layer
switch wsl <job> # A host, naming which project layer to use
switch --no-main # Build from current branch instead of main
switch --help    # Show all switch options
nix flake check --no-build  # Validate
nix fmt          # Format code
nix develop      # Enter devShell (installs pre-commit hooks)
```

## Critical Rules

- NEVER edit `hardware-configuration.nix` files manually, they are auto-generated
- NEVER edit the global agent rules at their deployed paths (`~/.claude/CLAUDE.md`, `~/.omp/agent/AGENTS.md`, `~/.omp/agent/RULES.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.config/opencode/AGENTS.md`, `~/.pi/agent/AGENTS.md`, `~/.config/agent-rules/`). They are all generated from `home/features/cli/agent-rules/`. Session-local notes go in `~/.claude/CLAUDE.local.md`, which Nix never overwrites
- ALWAYS validate with `nix flake check --no-build` before commit
- NEVER put personal data in the public repo, use nix-priv-personal for secrets and real values
- NEVER name an employer, client or their infrastructure anywhere in this repo, not in code, comments, filenames or `flake.lock`. That belongs in a project layer: the public repo offers options, a private layer turns them on
- NEVER add another identity's key to `vars.user.publicKey`. It feeds `authorizedKeys` on the personal hosts, so that is how a work machine would silently gain SSH into the homelab
- NEVER read a specialArg with a default (`terminalOnly`, `isServer`) from an `imports` position. The module system then resolves it through `_module.args`, which needs `config`, and that recurses. Gate conditional imports on a real option instead (see `modules.cli.syncthing.enable`)

## Hosts

|Host|Description|Desktop|Extras|
|---|---|---|---|
|`desktop`|Main PC|Hyprland/GNOME|NVIDIA, Steam, Gaming|
|`wsl`|WSL2|None|Docker, Pritunl|
|`vm`|Test VM|Hyprland/GNOME|QEMU, Waydroid|
|`homelab`|Server|None|Tailscale, Syncthing (encrypted), restic|

Home profiles without NixOS (`switch` activates home-manager only): `wrk` (employer-managed machine, terminal only, no graphical packages, no syncthing peer, `home/profiles/wrk/`) and `wsl-ubuntu` (Ubuntu WSL).

Stack: NixOS flakes with Home-Manager, Hyprland (Caelestia/Waybar) or GNOME, Matugen theming, SOPS-nix with Age, systemd-boot (Lanzaboote optional), Zsh, NVIDIA, Tailscale, Syncthing, NordVPN, restic. AI tools: Claude Code, Gemini CLI, OpenCode, pi.

## Project Structure

```
hosts/           # NixOS system configs per host
modules/         # core, desktop, drivers, services, secureboot (system-level)
home/
  default.nix    # Root HM config, imported by every NixOS host
  profiles/      # Standalone HM profiles (no NixOS): wrk, wsl-ubuntu
  features/      # cli, desktop, languages, programs
generators/      # ISO generation for installation
packages/        # Custom Nix packages
ci/              # empty-private placeholder: the `wrk` input default, and CI's
                 # stand-in for `private` when it has no repo access
scripts/         # Utility scripts (homelab-install)
docs/agents/     # On-demand agent docs, see below
```

## On-demand docs

Read a file only when its situation arises.

| File | Read when |
|---|---|
| `docs/agents/nix.md` | when editing Nix files: module patterns, specialArgs, `vars.nix` fields |
| `docs/agents/quality.md` | before committing, when reviewing a change, and before merging one |
| `docs/agents/layers.md` | when touching flake inputs, `switch`, `.private/` layers, the `wrk` profile, or SOPS secrets |
