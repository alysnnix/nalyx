# Design: Orca on the WSL host and on the employer-managed laptop

Date: 2026-09-08

## Goal

Run [Orca](https://www.onorca.dev) (stablyai/orca, MIT) as the front end for
the coding agents this repo already installs (`claude`, `opencode`, `gemini`),
on two machines:

1. **The WSL host** (`hosts/wsl`, NixOS-WSL). The Orca GUI runs on Windows and
   reaches the agents over SSH to `localhost:22`, following the topology in
   the reference article below. Editor and diff stay on Windows, agents and
   worktrees live in NixOS.
2. **The employer-managed laptop** (`home/profiles/wrk`, Ubuntu, standalone
   home-manager). Orca runs locally as a distro package. No SSH involved.

Reference for the WSL topology:
<https://zenn.dev/festiva1300/articles/orca-windows-wsl-ssh>

## Non-goals

- **Packaging Orca in nix.** There is no Orca derivation in nixpkgs (`orca`
  there is the GNOME screen reader, which is also why the Orca binary is named
  `orca-ide` on Linux). Upstream ships `.deb`, `.rpm`, AppImage, an `.exe` and
  macOS builds. On the WSL side the GUI is a Windows app by design; on the
  laptop the `.deb` is the right artifact for the reason `home/profiles/wrk`
  already documents: an osquery-based management agent inventories
  `deb_packages` and never `/nix/store`, so a graphical app pinned in a flake
  is both slower to patch and invisible to the dashboard watching for CVEs.
- **Enabling Orca on the personal graphical hosts** (`desktop`, `laptop`).
  Out of scope, but the option added here makes it a one-line change later.
- **Adding Codex CLI.** Orca supports it; this repo does not install it, and
  that stays a separate decision.
- **Cleaning up the dead firewall line** in `hosts/wsl/default.nix` (see
  Findings). Noted, not touched, so this change stays one thing.

## Findings from the live environment

All verified on the WSL host before writing this.

- **The article assumes Ubuntu in WSL; this host is NixOS-WSL 26.05.** Its
  steps 2, 4, 5 and 6 (`wsl --install -d Ubuntu`, `apt install openssh-server`,
  NVM, the `curl | sh` agent installers) do not apply and would fight the
  declarative config.
- **Mirrored networking is already configured** in `C:\Users\<user>\.wslconfig`
  (`networkingMode=mirrored`, `dnsTunneling=true`, `autoProxy=true`), which is
  the article's step 3 and the reason `localhost` works in both directions. The
  comment in that file claims NAT is used instead of mirrored, which
  contradicts the value below it; the interfaces confirm mirrored is active.
  That file is on the Windows side and outside this repo.
- **sshd is already enabled and reachable.** `services.openssh.enable = true`
  in `hosts/wsl/default.nix:124`, listening on `0.0.0.0:22`. `ssh.exe` from
  Windows to `aly@localhost` completes the handshake and fails only on
  authentication, so the whole network path already works.
- **Authentication is password-only today.** The `wsl` host is the one personal
  host that never adds `authorizedKeys` (`desktop`, `laptop` and `homelab` all
  add `vars.user.publicKey`), and the account carries the bootstrap
  `initialPassword = "changeme"` from `hosts/wsl/default.nix:175`. sshd offers
  `publickey,password,keyboard-interactive`.
- **The NixOS firewall is not running in WSL** (`firewall.service` inactive).
  So `networking.firewall.trustedInterfaces = [ "tailscale0" ]`
  (`hosts/wsl/default.nix:127`) is dead config here, and `openFirewall = false`
  would be a no-op. Inbound traffic to WSL is filtered by the Windows/Hyper-V
  firewall, not by anything this repo controls. Key-only authentication is
  therefore the only hardening lever available on this host.
- **The remote toolchain Orca needs is already present.** Orca installs a small
  relay on first connect and builds a native `node-pty` for remote terminals,
  which needs `make`, a C++ compiler and `python3`. Running a clean
  non-interactive shell the way sshd does (`env -i zsh -c ...`) resolves
  `node` (v22), `npm`, `git`, `python3`, `make`, `cc`, `g++`, `claude`,
  `opencode` and `gemini`, because `/etc/zshenv` sources NixOS'
  `set-environment` for every shell, interactive or not. The article's PATH
  troubleshooting (exporting NVM from `~/.profile`) has no analogue here.
- **`/mnt/c` is absent from that PATH**, so the article's "Orca picked the
  Windows node" failure cannot happen and `appendWindowsPath` can stay `true`.

## Decisions

### 1. `hosts/wsl`: key-only SSH for the Orca client

- Add `users.users.${vars.user.name}.openssh.authorizedKeys.keys` with two
  entries: `vars.user.publicKey`, matching the other three NixOS hosts, and a
  new key generated on the Windows side for Orca to use.
- Set `services.openssh.settings.PasswordAuthentication = false` and
  `KbdInteractiveAuthentication = false`.
- The Windows key is written inline in `hosts/wsl/default.nix`, with a comment,
  and deliberately **not** added to `vars.user.publicKey`: that attribute is
  the personal key alone by repo rule, and this one is a per-machine client
  key. A public key in a public repo leaks nothing.
- Adding `vars.user.publicKey` here is not incidental. Without it, turning
  password authentication off would lock out SSH into `wsl-nix` over Tailscale
  from the other personal hosts.

### 2. No nix change for the relay or the remote terminal

Verified present, so nothing is added speculatively. If `node-pty` fails on
first connect it is a bug to diagnose against real output, not config to
pre-empt.

### 3. `home/features/cli/orca` with `modules.cli.orca.enable`

The real problem on the laptop is that a GNOME Wayland session does not source
`~/.profile`, so an Orca launched from the application grid starts without
`~/.nix-profile/bin` on PATH and cannot find `claude`, `opencode`, `gemini` or
the nix `git`. The feature declares `modules.cli.orca.enable` (default `false`,
following `modules.cli.syncthing.enable` and `modules.wrk.pritunl.enable`) and,
when enabled, writes an `xdg.desktopEntries."orca-ide"` entry into
`~/.local/share/applications` that shadows the one from the `.deb` and wraps
the binary in a login shell:

```
Exec = "zsh -lc 'exec orca-ide %U'"
```

Chosen over exporting PATH for the whole graphical session through
`~/.config/environment.d/`: the wrapper touches exactly the one app that needs
the nix userland, instead of changing the environment every GUI process
inherits.

Enabled in `home/profiles/wrk`. Left off everywhere else.

## Manual steps outside nix

These are not automatable from this repo and are part of the deliverable as
documentation.

**Windows (for the WSL scenario)**

1. Install `orca-windows-setup.exe` from the upstream release.
2. `ssh-keygen -t ed25519 -C "orca-windows"` with a passphrase, then add it to
   the Windows `ssh-agent`.
3. Paste the public key into the `hosts/wsl` change above and rebuild.
4. Orca: Settings, Remote Hosts, SSH Host. Host `localhost`, port `22`, user
   `aly`, identity file pointing at the Windows key.

**Ubuntu laptop**

1. Download `orca-ide_<version>_amd64.deb` from the upstream release and
   `sudo apt install ./orca-ide_<version>_amd64.deb`. The `.deb` reports new
   versions and hands you the package-manager command; quit Orca before
   running it.
2. Rebuild the `wrk` home profile so the wrapped desktop entry lands.

## Verification

- `nix flake check --no-build` and `nix fmt`.
- From Windows: `ssh -i <key> aly@localhost 'command -v claude node make'`
  succeeds, and `ssh aly@localhost` with no key is refused (`Permission denied
  (publickey)`), proving password authentication is off.
- In Orca on Windows: the `wsl` target reports Connected, a worktree can be
  created on it, and a remote terminal opens (which is the `node-pty` build
  succeeding).
- On the laptop: launching Orca from the GNOME application grid, its terminal
  resolves `claude`, `opencode` and `gemini`.

## Risks

- Turning off password authentication makes the SSH key the only way in. The
  fallback if the key is lost is `wsl -u root` from Windows, which
  `hosts/wsl/default.nix` already documents for the locked-account case.
- The Windows private key sits on an NTFS filesystem. Mitigated with a
  passphrase plus the Windows `ssh-agent`; Orca holds passphrases in memory for
  the session.
- The desktop-entry wrapper shadows a file owned by the `.deb`. If a future
  Orca release changes its `Exec` line or icon name, the shadow keeps the old
  one and has to be updated by hand.
