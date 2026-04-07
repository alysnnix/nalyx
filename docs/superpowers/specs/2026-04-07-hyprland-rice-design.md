# Hyprland Rice Design: Minimal Caelestia

**Date:** 2026-04-07
**Status:** Approved

## Overview

Integrate [caelestia-dots/shell](https://github.com/caelestia-dots/shell) into the nalyx NixOS config as the unified Hyprland desktop shell, replacing the current Waybar + Rofi + Dunst stack. The goal is a cohesive, minimalist desktop with rounded corners, dynamic wallpaper-based colors (Matugen), and snappy animations.

All changes are scoped to `home/features/desktop/hyprland/` and guarded by `vars.desktop == "hyprland"`. GNOME and other hosts are unaffected.

## Security Audit

Full supply chain audit performed (2026-04-07) covering all three components:

```
caelestia-dots/shell (QML, 42k lines) ── audited, 0 CRITICAL, 5 WARNING
├── caelestia-cli (Python, ~30 files) ── audited, 0 CRITICAL, 4 WARNING
└── quickshell (C++, 57k lines) ──────── audited, 3 CRITICAL (by-design), 5 WARNING
```

### caelestia-dots/shell (8.6k stars, GPL-3.0)

| ID | Issue | Risk | Mitigation |
|----|-------|------|------------|
| S-W1 | Command injection in LyricsService (MPRIS metadata) | Low (requires local access) | Lyrics disabled entirely |
| S-W2 | IP geolocation request to ipinfo.io | Privacy | Set weather coordinates explicitly in nalyx-private |
| S-W3 | Lyrics fetched from NetEase (music.163.com) | Privacy | Lyrics disabled entirely |
| S-W4 | Quickshell fetched from git.outfoxxed.me (self-hosted Gitea) | Supply chain | Pin Quickshell to GitHub mirror (see below) |
| S-W5 | Maintainer pushed prank commit to main (April Fools 2026) | Governance | Pin to audited revision, never follow main head |

Clean: Nix integration, CMake build, C++ plugins, shell scripts, QML/JS code, GitHub Actions. Zero telemetry.

### caelestia-cli (135 stars, GPL-3.0, Python)

| ID | Issue | Risk | Mitigation |
|----|-------|------|------------|
| C-W1 | `postHook` config uses `shell=True` (arbitrary command execution) | Medium (requires write to config file) | Do not configure postHook |
| C-W2 | `sudo papirus-folders` for icon color sync (optional) | Low (fails silently without sudoers) | Do not configure sudoers for papirus-folders |
| C-W3 | Writes ANSI sequences to `/dev/pts/*` for live terminal color updates | Info | Standard behavior (pywal does the same) |
| C-W4 | Transitive Quickshell dependency from self-hosted Forgejo | Supply chain | Pin to GitHub mirror (see below) |

Clean: No telemetry, no data exfiltration, no eval/exec on dynamic input, no binary blobs. Network calls only for emoji data fetch (explicit command, GitHub raw URLs only).

### quickshell (2.2k stars, LGPL-3.0, C++ / Qt6)

The CRITICAL findings are **architectural, not bugs** -- every desktop shell framework (Waybar, AGS, Eww) requires these capabilities to function. The real question is whether the QML configs loaded into Quickshell are trustworthy (yes -- audited above).

| ID | Issue | Risk | Mitigation |
|----|-------|------|------------|
| Q-C1 | QML has unrestricted process execution (`Process`, `execDetached`) | CRITICAL (by design) | Trust gate: only load audited QML (caelestia-dots/shell) |
| Q-C2 | QML has unrestricted filesystem read/write (`FileView`) | CRITICAL (by design) | Trust gate: only load audited QML |
| Q-C3 | QML has unrestricted Unix socket access (`Socket`, `SocketServer`) | CRITICAL (by design) | Trust gate: only load audited QML |
| Q-W1 | Self-hosted Forgejo as primary upstream | Supply chain | **Pin to GitHub mirror** (`quickshell-mirror/quickshell`), verified GPG-signed commits |
| Q-W2 | Single maintainer (91.9% of commits) | Governance | Pin to audited revision, review diffs before updating |
| Q-W3 | PAM authentication subprocess (lock screen) | Medium | Runs as user, not root |
| Q-W4 | Polkit agent can present privilege escalation prompts | Medium | Standard desktop behavior |
| Q-W5 | Screencopy, clipboard read/write, env var access from QML | Medium | Standard desktop shell capabilities |

Clean: Zero telemetry, zero pre-compiled binaries, zero obfuscated code, Nix packaging is minimal and standard, no outgoing network connections in codebase, all Wayland protocols are standard community protocols.

### Supply chain hardening rules

1. **Pin all inputs to audited revisions** -- never follow main/dev head
2. **Override Quickshell input to GitHub mirror** (`quickshell-mirror/quickshell`) instead of self-hosted Forgejo
3. **Do not configure** `postHook` in caelestia CLI config
4. **Do not configure** sudoers for `papirus-folders`
5. **Review diffs before any `nix flake update`** on caelestia/quickshell inputs

## Flake Integration

Add caelestia-dots/shell as a flake input pinned to a specific audited revision. Override the Quickshell input to use the GitHub mirror instead of the self-hosted Forgejo:

```nix
# flake.nix inputs
caelestia = {
  url = "github:caelestia-dots/shell/<audited-revision>";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.quickshell.url = "github:quickshell-mirror/quickshell/<audited-revision>";
};
```

This ensures:
- caelestia is pinned to an audited commit on GitHub
- Quickshell is pinned to the GitHub mirror (same code, verified GPG-signed commits, stronger trust anchor than self-hosted Forgejo)
- nixpkgs is deduplicated via `follows`

Pass the `caelestia` input to Home Manager modules via `extraSpecialArgs`.

## Module Structure

```
home/features/desktop/hyprland/
├── default.nix              # Main module (mkIf guard kept)
├── hyprland.conf            # Rewritten: keybinds, rules, visual
├── caelestia/
│   └── default.nix          # Caelestia HM module + security config
├── matugen/
│   ├── default.nix          # Activate templates for non-Quickshell apps
│   └── templates/           # Existing templates
└── scripts/                 # Helper scripts if needed
```

### What changes

- Waybar and Rofi modules are no longer imported (replaced by Quickshell)
- Dunst is removed from packages (caelestia handles notifications)
- Matugen stays active for apps outside Quickshell (Kitty, GTK, Btop, Hyprland borders)
- hyprland.conf rewritten with new keybinds and visual settings

### What does not change

- The `lib.mkIf (vars.desktop == "hyprland")` guard in default.nix
- The conditional import in `home/default.nix`
- GNOME modules, host configs, flake structure (beyond the new input)

## Caelestia Configuration

### Security hardening

```nix
{
  # W2: No IP geolocation -- use explicit coordinates from private repo
  services.weatherLocation = vars.weather.location;

  # W1/W3: No music metadata sent to external services
  services.showLyrics = false;

  # Prevent accidental shutdown/reboot from launcher
  launcher.enableDangerousActions = false;
}
```

### Modules disabled (minimalism)

- Dashboard / media controls widget
- Audio visualizer (cava)
- Lyrics display

### Modules enabled

- Bar: workspaces, clock, volume, network, CPU/RAM, system tray
- Launcher: app search with autocomplete
- Notifications
- OSD: volume/brightness indicators
- Lock screen (hyprlock)

## Private Repo Changes

Add to `nalyx-private/vars-override.nix`:

```nix
{
  weather.location = "<real-lat>,<real-lon>";
}
```

This is the only change in nalyx-private. All other config is in the public repo with safe defaults.

Add corresponding default to public `vars.nix`:

```nix
{
  weather.location = "";  # Override in private repo
}
```

## Keybinds

| Shortcut | Action | Hyprland bind |
|----------|--------|---------------|
| `SUPER` (release) | Toggle launcher | `bindr = SUPER, SUPER_L, exec, <launcher-toggle>` (exact command determined during implementation by reading caelestia source -- likely `caelestia` CLI or Quickshell IPC) |
| `SUPER+Return` | Terminal (kitty) | `bind = SUPER, Return, exec, kitty` |
| `SUPER+W` | Close window | `bind = SUPER, W, killactive` |
| `SUPER+F` | Fullscreen | `bind = SUPER, F, fullscreen` |
| `SUPER+Arrows` | Move focus | `bind = SUPER, <dir>, movefocus, <dir>` |
| `SUPER+ALT+Left` | Previous workspace | `bind = SUPER ALT, left, workspace, e-1` |
| `SUPER+ALT+Right` | Next workspace | `bind = SUPER ALT, right, workspace, e+1` |
| `SUPER+C` | Calculator | `bind = SUPER, C, exec, qalculate-gtk` |
| `SUPER+E` | File explorer | `bind = SUPER, E, exec, nautilus` |
| `SUPER+M` | Email (Thunderbird) | `bind = SUPER, M, exec, thunderbird` |
| `SUPER+B` | Browser (Chrome) | `bind = SUPER, B, exec, google-chrome-stable` |
| `SUPER+,` | GTK settings | `bind = SUPER, comma, exec, nwg-look` |
| `Print` | Screenshot to clipboard | `bind = , Print, exec, grim -g "$(slurp)" - \| wl-copy` |

## Visual Settings

### Hyprland decorations

```conf
general {
    gaps_in = 5
    gaps_out = 12
    border_size = 2
    col.active_border = <matugen-primary>
    col.inactive_border = <matugen-surface>
    layout = dwindle
}

decoration {
    rounding = 12
    blur {
        enabled = true
        size = 4
        passes = 2
        vibrancy = 0.17
    }
    shadow {
        enabled = true
        range = 8
        render_power = 3
    }
}

animations {
    enabled = yes
    bezier = smooth, 0.25, 0.1, 0.25, 1
    bezier = snappy, 0.4, 0, 0.2, 1
    animation = windows, 1, 4, snappy, popin 85%
    animation = fade, 1, 3, smooth
    animation = workspaces, 1, 3, snappy, slide
    animation = border, 1, 5, smooth
}
```

### Design principles

- Rounding 12px on all components (windows, bar, launcher, notifications)
- Moderate blur (not frosted glass, not absent)
- Balanced gaps (5px inner, 12px outer)
- Snappy animations (fast, not slow) -- popin for windows, slide for workspaces
- Dynamic border colors from Matugen

## Color Architecture: Matugen + Caelestia

Caelestia has its own internal color/scheme system. Matugen generates colors from wallpapers. These two systems serve different scopes:

- **Caelestia** handles its own UI colors (bar, launcher, notifications, OSD, lock screen). Its scheme system is configured via caelestia settings. During implementation, we will investigate whether caelestia can consume Matugen-generated colors or if it needs its own wallpaper-to-color pipeline.
- **Matugen** handles colors for apps outside Quickshell (Hyprland borders, Kitty, GTK, Btop).

If caelestia cannot consume Matugen colors, the fallback is: Matugen generates a palette from the wallpaper for external apps, and caelestia uses its built-in scheme system (which may have its own wallpaper-based generation). Both systems would use the same wallpaper as source, ensuring visual cohesion even if the exact hex values differ slightly.

## Matugen Theming

### Active templates

| App | Template | Reload method |
|-----|----------|---------------|
| Hyprland | `hyprland-colors.conf` | `hyprctl reload` |
| Kitty | `kitty-colors.conf` | Kitty auto-reloads |
| GTK | `gtk-colors.css` | Restart GTK apps |
| Btop | `btop.theme` | Restart btop |

### Deactivated templates (previously active, replaced by Quickshell)

- Waybar colors (caelestia handles bar theming)
- Rofi colors (caelestia handles launcher theming)

### Future templates (activate on demand)

- Neovim, Yazi, Alacritty, Ghostty, and 20+ others already in templates/

## Packages

Added to Home Manager (Hyprland-only):

- `google-chrome` (browser, unfree)
- `thunderbird` (email)
- `qalculate-gtk` (calculator)
- `nwg-look` (GTK settings)
- `grim` + `slurp` (screenshot, already present)
- `wl-clipboard` (clipboard, already present)
- `swww` (wallpaper daemon, already present)

Removed:

- `rofi` (replaced by caelestia launcher)
- `dunst` (replaced by caelestia notifications)

Waybar package stays if other modules reference it, but is no longer imported in Hyprland.

## Conditional Guard

The entire integration is protected by the existing two-level guard:

**Level 1 -- import gate** (`home/default.nix`):
```nix
++ (lib.optional (vars.desktop == "hyprland") ./features/desktop/hyprland)
```

**Level 2 -- config gate** (`hyprland/default.nix`):
```nix
config = lib.mkIf (vars.desktop == "hyprland") { ... };
```

When `vars.desktop == "gnome"`, the Hyprland module tree is never imported and never evaluated. Zero cross-contamination.

## Testing Strategy

1. Set `vars.desktop = "hyprland"` (or override in private)
2. Build with `nix build .#nixosConfigurations.vm.config.system.build.toplevel` to validate
3. Test in VM (Hyprland on NVIDIA via WSL)
4. Verify GNOME still builds: `nix build .#nixosConfigurations.desktop.config.system.build.toplevel` with `desktop = "gnome"`
5. Later: deploy to laptop (Intel)

## Approach

**Config-only (Approach 1):** Use caelestia's HM module and configure via exposed options. If we hit a limitation, escalate to QML overrides (Approach 2) for specific components.

## Open Questions (resolve during implementation)

1. **Exact launcher toggle command** -- read caelestia source to determine IPC/CLI mechanism
2. **Caelestia + Matugen color integration** -- can caelestia consume Matugen-generated colors, or does it need its own pipeline?
3. **Audited revision** -- determine the latest stable revision of caelestia-dots/shell to pin
4. **Caelestia HM module options** -- read `nix/hm-module.nix` to map our config requirements to actual module options
5. **NVIDIA compatibility** -- test blur/animations performance on NVIDIA (VM first)
