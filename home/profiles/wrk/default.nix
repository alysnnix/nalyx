{
  pkgs,
  vars,
  lib,
  config,
  ...
}:
# Work profile: terminal only, standalone home-manager, no employer named.
#
# For a machine an employer manages: their OS image, their device management
# agent, their disk encryption policy. Nix owns the userland and nothing else.
# The immediate driver is that osquery-based agents ship as .deb or .rpm and
# bundle a self-updating binary tree, which no immutable store can host, so the
# system layer has to be the distro's. That trade turns out to be the right one
# anyway: the agent stays on its vendor's tested path, and this config stops
# being responsible for a machine it does not own.
#
# This file names no company, and nothing under it may. Employer-specific
# values (the committer address, extra signers, private skills, secrets, the
# tools only that job needs) come from the `wrk` flake input, which defaults to
# the empty placeholder and is pointed at a private per-project repo by
# `switch`. That keeps this repo publishable and lets a second or third job be
# added later without touching it.
#
# It does NOT import ../default.nix on purpose. That file holds the graphical
# packages and the gtk/qt theming, and a managed laptop wants none of it.
# Graphical apps come from the distro's package manager, deliberately: an
# osquery agent inventories deb_packages and never /nix/store, so a browser
# pinned in a flake both lags behind CVEs and stays invisible to the compliance
# dashboard that is supposed to be watching it.
let
  # Wrapped rather than inlined so shellcheck runs on it at build time.
  pritunlSetup = pkgs.writeShellApplication {
    name = "wrk-pritunl-setup";
    runtimeInputs = [ pkgs.systemd ];
    text = builtins.readFile ./scripts/pritunl-setup.sh;
  };
in
{
  options.modules.wrk.pritunl.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Install the Pritunl VPN client and the helper that registers its daemon.

      Default true because a managed work machine almost always sits behind a
      corporate VPN, and this profile exists for exactly that machine. A job
      that uses something else turns it off from its private module.

      Note the nixpkgs derivation bundles the CLI, an electron app and its
      .desktop entry, and they cannot be separated without an override that
      would drift from upstream. It is the one entry in this profile that puts
      a window on screen.
    '';
  };

  # Languages are listed one by one rather than pulling ../../features/languages,
  # so this file stays the single place that says what the work machine gets.
  # `latex` is the one left out: it is an academic toolchain, and it drags in
  # texlive-combined-medium plus a graphical PDF viewer and an X-linked
  # ghostscript, none of which belong on a work laptop.
  imports = [
    ../../features/cli
    ../../features/languages/go
    ../../features/languages/nix
    ../../features/languages/node
    ../../features/languages/java
    ../../features/languages/python

    # Reached into ../features/programs on purpose. That tree is gated on
    # hasDesktop, but this one holds nothing graphical: docker-client,
    # docker-compose, lazydocker, hadolint and trivy are all CLI. The daemon
    # itself has always come from the system, so the distro provides it here.
    ../../features/programs/docker
  ];

  config = {
    home = {
      # mkDefault so the project layer can replace both.
      #
      # The login account on an employer-managed machine is usually not the
      # personal one, and a standalone home-manager generation bakes these
      # paths in verbatim: take the wrong name and the generation is rooted at
      # a home directory that user cannot even create. The right name is a
      # property of the job, not of this repo, so the layer supplies it and
      # this repo keeps naming nobody.
      #
      # The git identity is unaffected either way: features/cli/git reads
      # vars.user, so authorship stays personal regardless of the login name.
      username = lib.mkDefault vars.user.name;
      homeDirectory = lib.mkDefault "/home/${vars.user.name}";

      # Short by design. The nerd font is not optional because
      # ../../features/cli/ghostty pins `JetBrainsMono Nerd Font` in its
      # config, and a terminal without its glyphs is a broken terminal.
      # Anything graphical that ../default.nix used to add is gone.
      packages =
        with pkgs;
        [
          gh
          gnumake
          nerd-fonts.jetbrains-mono

          # Terminal tools that only ever lived inside ../../features/programs,
          # which is gated on hasDesktop, so dropping that tree stranded them.
          # Listed here rather than moved, to keep every other host's closure
          # identical.
          k6
          vegeta
          postgresql # the psql client, not a server
        ]
        ++ lib.optionals config.modules.wrk.pritunl.enable [
          # The CLI alone does not connect: it talks to pritunl-client-service,
          # which needs root. `wrk-pritunl-setup` registers that system unit and
          # has to be run once by hand (see scripts/pritunl-setup.sh).
          pritunl-client
          pritunlSetup
        ];

      sessionVariables = {
        EDITOR = vars.editor;
      };

      stateVersion = "25.11";
    };

    # Work committer identity.
    #
    # It cannot live in vars, because this repo is public and the address is an
    # employer one, so putting it there publishes an employee address to every
    # fork, mirror and scraper, permanently. So git reads it from a file this
    # config deliberately does not own. Verified that home-manager emits the
    # [include] after the [user] block and git takes the last value, so this
    # wins over vars.user.email.
    #
    # A per-project private module may write the file from its own secret
    # instead, which is the declarative version of the same thing.
    #
    # Signing needs no override: the key path is the same ~/.ssh/id_ed25519 on
    # that host, holding whichever key material belongs to that job.
    programs.git.includes = [
      { path = "${config.home.homeDirectory}/.config/git/identity"; }
    ];

    # The include silently falling back to the personal address is the failure
    # mode worth shouting about: commits would land in the employer's repos
    # attributed to the wrong identity and nobody notices for weeks.
    home.activation.checkGitIdentity = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -s "$HOME/.config/git/identity" ]; then
        echo "warning: ~/.config/git/identity is missing, so commits will use ${vars.user.email}"
        echo "         write the work address there, see home/profiles/wrk/default.nix"
      fi
    '';

    # No Syncthing peer here. The point of a managed machine is that it stops
    # being a node in the personal fleet, so it must not even carry the ignore
    # list for a folder it is never going to sync.
    modules.cli.syncthing.enable = false;

    # Not NixOS, so nothing sets up the session for a nix profile. This exports
    # XDG_DATA_DIRS and friends via hm-session-vars.sh, which is what makes
    # completions, man pages and desktop entries from the profile resolvable.
    targets.genericLinux.enable = true;

    # On NixOS the nerd fonts are installed system wide by `fonts.packages` in
    # modules/core, an option that does not exist off NixOS. Without this the
    # font sits in the profile and fontconfig never indexes it, so ghostty
    # silently falls back and the glyphs disappear.
    fonts.fontconfig.enable = true;

    # Same guard as ../default.nix: a leftover backup file aborts activation,
    # and standalone home-manager hits this more often since it is invoked by
    # hand rather than by a system rebuild.
    home.activation.cleanBackups = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      find ~/.config -name "*.backup-*" -delete 2>/dev/null || true
    '';

    programs.home-manager.enable = true;
  };
}
