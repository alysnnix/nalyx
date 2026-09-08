# Nalyx

Personal NixOS configuration. Public, employer-neutral, with pluggable private layers.

## Quick Start

```bash
switch           # Build system (switches to main, auto-detects hostname)
switch wsl       # Specify a host
switch szn       # The wrk profile with the .private/szn-private layer
switch wsl szn   # A host, naming which project layer to use
switch --no-main # Build from current branch instead of main
switch --help    # Show all switch options
nix flake check --no-build  # Validate
nix fmt          # Format code
nix develop      # Enter devShell (installs pre-commit hooks)
```

## Critical Rules

- NEVER edit `hardware-configuration.nix` files manually — they are auto-generated
- NEVER edit the global agent rules at their deployed paths (`~/.claude/CLAUDE.md`, `~/.omp/agent/AGENTS.md`, `~/.omp/agent/RULES.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.config/opencode/AGENTS.md`). They are all generated from `home/features/cli/agent-rules/`. Session-local notes go in `~/.claude/CLAUDE.local.md`, which Nix never overwrites
- ALWAYS validate with `nix flake check --no-build` before commit
- NEVER put personal data in the public repo, use nalyx-private for secrets and real values
- NEVER name an employer, client or their infrastructure anywhere in this repo, not in code, comments, filenames or `flake.lock`. That belongs in a project layer. A public config that says who you work for is a liability you cannot take back once pushed
- NEVER read a specialArg with a default (`terminalOnly`, `isServer`) from an `imports` position. The module system then resolves it through `_module.args`, which needs `config`, and that recurses. Gate conditional imports on a real option instead (see `modules.cli.syncthing.enable`)

## Layer Architecture

Three kinds of repo. This one is public and names nobody; the others are private and fill in what it deliberately leaves blank.

| Repo | Holds | Flake input |
|---|---|---|
| `nalyx` (here) | everything publishable: hosts, features, options | |
| `nalyx-private` | the person: personal secrets, personal repos, the syncthing fleet | `private` |
| `<project>-private` | one employer or client: their identity, secrets, skills, tools | `wrk` |

Both inputs are optional and detected with `private ? null` / `wrk ? null`, so a clone with neither still builds: safe defaults, `initialPassword = "changeme"`, SOPS disabled.

### The rule

**The public repo offers options; a private layer turns them on.** Anything employer-specific is an option here and a value there. Current examples:

- `modules.cli.git.extraSigners` (`home/features/cli/git/options.nix`)
- `modules.wrk.pritunl.enable` (`home/features/cli/wrk.nix`)
- `modules.cli.syncthing.enable` (`home/features/cli/syncthing`)

A layer plugs in by exporting `homeManagerModules.default`, and `nixosModules.default` when it has secrets to declare. The helpers in `flake.nix` are `privateHmModules`, `privateNixosModules`, `privateNixosModule <name>`, `wrkHmModules`, `wrkNixosModules`.

### Why the `wrk` input defaults to a local path

A flake input is static and lives in `flake.nix`, so any real URL there would publish the name it exists to hide. `wrk` therefore defaults to `path:./ci/empty-private` and `switch` overrides it per machine. The project layer's own `flake.lock` carries the employer's URLs, so they never reach a public lock file.

`private` still defaults to a URL, because `nalyx-private` names nobody.

### How `switch` picks the layers

Which layers a machine gets is decided by **what is cloned into `.private/`**, nothing else. `switch` discovers any directory there with a `flake.nix`: `nalyx-private` is the personal layer, anything else is a project layer (`.private/notes` is skipped for having no flake). It addresses a project by its directory name minus the `-private` suffix, so `.private/szn-private` is `switch szn`.

With one project layer cloned the name is optional. With several it is required, because a flake takes one `wrk` input and NixOS hosts carry the layer too: `switch wsl szn`.

The work laptop simply never clones `nalyx-private`, and that absence is the whole isolation mechanism.

### Secrets

Each private repo owns its own SOPS file and its own recipients, and a project layer must set `sopsFile` explicitly on every secret, because `sops.defaultSopsFile` is a single value already claimed by the personal layer.

The recipient lists are deliberately asymmetric: a project file lists the personal age key **and** the machine key for that job, so every personal machine reads it; the personal file lists only the personal key, so an employer-managed machine cannot read it even if it somehow got the repo. Recipients are derived from SSH keys with `ssh-to-age`, and each key decrypts independently, so no private key is ever copied between machines.

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
| Services | Tailscale, Syncthing, NordVPN, Hermes Agent |

## Hosts

| Host | Description | Desktop | Extras |
|------|-------------|---------|--------|
| `desktop` | Main PC | Hyprland/GNOME | NVIDIA, Steam, Gaming |
| `laptop` | Notebook | Hyprland/GNOME | Intel, KDE Connect |
| `wsl` | WSL2 | None | Docker, Pritunl, Playwright |
| `vm` | Test VM | Hyprland/GNOME | QEMU, Waydroid |
| `homelab` | Server | None | Tailscale, Hermes Agent |

### Home profiles (no NixOS)

| Profile | For |
|---|---|
| `wrk` | an employer-managed machine: terminal only, no graphical packages, no syncthing peer. `home/profiles/wrk/` |
| `wsl-ubuntu` | Ubuntu WSL without NixOS |

On these, `switch` activates home-manager instead of `nixos-rebuild`, since the system layer belongs to the distro. Graphical apps there come from the distro's package manager on purpose: an osquery-based management agent inventories `deb_packages`, never `/nix/store`, so a browser pinned in a flake both lags behind CVEs and stays invisible to the dashboard watching for them.

## Project Structure

```
hosts/           # NixOS system configs per host
modules/
  core/          # Base system (all hosts)
  desktop/       # Hyprland, GNOME (system-level)
  drivers/       # NVIDIA, Intel
  services/      # NordVPN, Syncthing, Hermes Agent
  secureboot/    # Lanzaboote (optional)
home/
  default.nix    # Root HM config, imported by every NixOS host
  profiles/      # Standalone HM profiles (no NixOS)
    wrk/         # Employer-managed machine: terminal only
  features/
    cli/         # zsh, git, ssh, neovim, claude, gemini, opencode
    desktop/     # hyprland (caelestia/waybar/rofi/matugen), gnome
    languages/   # go, java, latex, nix, node, python
    programs/    # docker, firefox, games, obs, vscode, zed
generators/      # ISO generation for installation
packages/        # Custom Nix packages
ci/              # empty-private placeholder: the `wrk` input default, and CI's
                 # stand-in for `private` when it has no repo access
scripts/         # Utility scripts (homelab-install)
```

## Code Conventions

- Module pattern: `{ pkgs, vars, lib, config, ... }:`
- Conditional imports: `lib.optional (vars.desktop == "hyprland") ./hyprland`
- HM special args: `isWsl`, `isServer`, `terminalOnly`, `enableClaude`, `enableGemini`, `enableOpencode`. Every one is passed at all four `extraSpecialArgs` sites (`fnMountSystem`, the two home profiles, `generators/`); the `? default` in each module signature is documentation, not a fallback that fires
- Directories: `kebab-case`, main files: `default.nix`
- Host helper: `fnMountSystem` in `flake.nix` builds each host config

## Key Variables (`vars.nix`)

- `vars.user.name`, `vars.user.email`, `vars.user.publicKey`
- `vars.user.publicKey` is the personal key alone, and feeds `authorizedKeys` on the personal hosts. Never add another identity's key to it: that is how a work machine would silently gain SSH into the homelab
- `vars.user.signers` is the list of identities to verify commit signatures from, written to `~/.ssh/allowed_signers`. Principals are ssh-keygen patterns, so a project layer registers `*@employer.example` through `modules.cli.git.extraSigners` without the address landing here
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
