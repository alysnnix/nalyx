{
  pkgs,
  vars,
  lib,
  ...
}:
# Seazone work laptop: terminal only, standalone home-manager.
#
# That machine runs Seazone's own Ubuntu image with the Fleet agent, so the
# system layer is theirs and NixOS never lands there. Fleet's Linux support
# covers osquery visibility plus remote script execution as root, and NixOS is
# not on its supported distro list, so fighting to package fleetd against an
# immutable store would leave the host permanently drifting out of compliance.
# Nix owns the userland instead, which is where declarativeness actually pays.
#
# This profile does NOT import ../default.nix on purpose. That file is where
# the graphical packages live (obsidian, chrome, slack, spotify and the whole
# features/programs tree) along with the gtk/qt theming, and none of it belongs
# here. Graphical apps come from apt/snap on that host, deliberately: Fleet
# inventories deb_packages, never /nix/store, so a browser pinned in a flake
# both lags behind CVEs and stays invisible to their compliance dashboard.
#
# The private flake module is intentionally absent as well. It clones personal
# repos (features/cli/wrk.nix) and reads every secret from /run/secrets, which
# only the sops-nix NixOS module creates. Wiring the Seazone layer up here
# needs the secrets file split into a work-only set first; until then the
# agents run on the public generic config.
{
  # Languages are listed one by one rather than pulling ../features/languages,
  # so this file stays the single place that says what the work machine gets.
  # `latex` is the one left out: it is the university toolchain, not a Seazone
  # one, and it drags in texlive-combined-medium plus a graphical PDF viewer
  # (zathura) and an X-linked ghostscript.
  imports = [
    ../features/cli
    ../features/languages/go
    ../features/languages/nix
    ../features/languages/node
    ../features/languages/java
    ../features/languages/python

    # Reached into ../features/programs on purpose. That tree is gated on
    # hasDesktop, but this one holds nothing graphical: docker-client,
    # docker-compose, lazydocker, hadolint and trivy are all CLI. The daemon
    # itself has always come from the system, so apt provides it here.
    ../features/programs/docker
  ];

  home = {
    username = vars.user.name;
    homeDirectory = "/home/${vars.user.name}";

    # Short by design. `gh` and `gnumake` are terminal tools; the nerd font is
    # not optional because features/cli/ghostty pins `JetBrainsMono Nerd Font`
    # in its config, and a terminal without its glyphs is a broken terminal.
    # Anything graphical that used to sit here (obsidian) is gone.
    packages = with pkgs; [
      gh
      gnumake
      nerd-fonts.jetbrains-mono

      # Terminal tools that only ever lived inside ../features/programs, which
      # is gated on hasDesktop, so dropping that tree stranded them. Listed
      # here rather than moved, to keep every other host's closure identical.
      k6
      vegeta
      postgresql # the psql client, not a server
    ];

    sessionVariables = {
      EDITOR = vars.editor;
    };

    stateVersion = "25.11";
  };

  # No Syncthing peer here. The whole point of moving to a managed laptop is
  # that it stops being a node in the personal fleet, so it must not even carry
  # the ignore list for a folder it is never going to sync.
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

  # Same guard as ../default.nix: a leftover backup file aborts activation, and
  # standalone home-manager hits this more often since it is invoked by hand.
  home.activation.cleanBackups = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    find ~/.config -name "*.backup-*" -delete 2>/dev/null || true
  '';

  programs.home-manager.enable = true;
}
