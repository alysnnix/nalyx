# Private Layers and Secrets

Three kinds of repo. This one is public and names nobody; the others are private and fill in what it deliberately leaves blank.

|Repo|Holds|Flake input|
|---|---|---|
|`nalyx` (here)|everything publishable: hosts, features, options||
|`nix-priv-personal`|the person: personal secrets, personal repos, the syncthing fleet|`private`|
|`nix-priv-<project>`|one employer or client: their identity, secrets, skills, tools|`wrk`|

Both inputs are optional and detected with `private ? null` / `wrk ? null`, so a clone with neither still builds: safe defaults, `initialPassword = "changeme"`, SOPS disabled.

## The rule

**The public repo offers options; a private layer turns them on.** Anything employer-specific is an option here and a value there. Current examples:

- `modules.cli.git.extraSigners` (`home/features/cli/git/options.nix`)
- `modules.wrk.pritunl.enable` (`home/features/cli/wrk.nix`)
- `modules.cli.syncthing.enable` (`home/features/cli/syncthing`)

A layer plugs in by exporting `homeManagerModules.default`, and `nixosModules.default` when it has secrets to declare. The helpers in `flake.nix` are `privateHmModules`, `privateNixosModules`, `privateNixosModule <name>`, `wrkHmModules`, `wrkNixosModules`.

## Why the `wrk` input defaults to a local path

A flake input is static and lives in `flake.nix`, so any real URL there would publish the name it exists to hide. `wrk` therefore defaults to `path:./ci/empty-private` and `switch` overrides it per machine. The project layer's own `flake.lock` carries the employer's URLs, so they never reach a public lock file.

`private` still defaults to a URL, because `nix-priv-personal` names nobody.

## How `switch` picks the layers

Which layers a machine gets is decided by **what is cloned into `.private/`**, nothing else. `switch` discovers any directory there with a `flake.nix`: `nix-priv-personal` is the personal layer, anything else is a project layer (`.private/notes` is skipped for having no flake). It addresses a project by its directory name minus the `nix-priv-` prefix, so `.private/nix-priv-<job>` is `switch <job>`.

With one project layer cloned the name is optional. With several it is required, because a flake takes one `wrk` input and NixOS hosts carry the layer too: `switch wsl <job>`.

The work laptop simply never clones `nix-priv-personal`, and that absence is the whole isolation mechanism.

## Home profiles on employer machines

On the `wrk` and `wsl-ubuntu` profiles, `switch` activates home-manager instead of `nixos-rebuild`, since the system layer belongs to the distro. Graphical apps there come from the distro's package manager on purpose: an osquery-based management agent inventories `deb_packages`, never `/nix/store`, so a browser pinned in a flake both lags behind CVEs and stays invisible to the dashboard watching for them.

## Secrets

Each private repo owns its own SOPS file and its own recipients, and a project layer must set `sopsFile` explicitly on every secret, because `sops.defaultSopsFile` is a single value already claimed by the personal layer.

The recipient lists are deliberately asymmetric: a project file lists the personal age key **and** the machine key for that job, so every personal machine reads it; the personal file lists only the personal key, so an employer-managed machine cannot read it even if it somehow got the repo. Recipients are derived from SSH keys with `ssh-to-age`.

The personal layer is split the same way, and for a sharper reason: the homelab stores an encrypted copy of `~/wrk`, so it must not be able to read the passwords that open it. `secrets/machines.yaml` (personal key plus the homelab's **host** key) holds only what a machine needs to finish booting and reach the tailnet; `secrets/secrets.yaml` (personal key alone) holds everything else, including the two backup passwords. A host key rather than a user key, because it exists before `/home` is mounted, which `neededForUsers` secrets require, and because it is worth far less if that machine is taken.

The homelab still carries the personal key as a decryption fallback, so it can currently read both files. That is a deliberate transition step, not the end state: it is headless, on WiFi, and takes its WiFi password from SOPS, so a wrong recipient with no fallback would strand it. Phase 2 removes the fallback and the key from that machine. Until then, do not describe the homelab as unable to read a personal secret. See `SECURITY.md` in the private repo.
