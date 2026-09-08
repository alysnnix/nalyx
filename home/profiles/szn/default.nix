{
  pkgs,
  vars,
  lib,
  config,
  ...
}:
let
  # Wrapped rather than inlined so shellcheck runs on it at build time.
  pritunlSetup = pkgs.writeShellApplication {
    name = "szn-pritunl-setup";
    runtimeInputs = [ pkgs.systemd ];
    text = builtins.readFile ./scripts/pritunl-setup.sh;
  };
in
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
  # Languages are listed one by one rather than pulling ../../features/languages,
  # so this file stays the single place that says what the work machine gets.
  # `latex` is the one left out: it is the university toolchain, not a Seazone
  # one, and it drags in texlive-combined-medium plus a graphical PDF viewer
  # (zathura) and an X-linked ghostscript.
  imports = [
    ../../features/cli
    ../../features/languages/go
    ../../features/languages/nix
    ../../features/languages/node
    ../../features/languages/java
    ../../features/languages/python

    # Reached into ../../features/programs on purpose. That tree is gated on
    # hasDesktop, but this one holds nothing graphical: docker-client,
    # docker-compose, lazydocker, hadolint and trivy are all CLI. The daemon
    # itself has always come from the system, so apt provides it here.
    ../../features/programs/docker
  ];

  home = {
    # Literal, and the one place in the tree that does not read vars.user.name.
    # That value is the personal login name; the account on the work laptop is
    # a different one, and this has to match the account that runs the
    # activation. A standalone home-manager generation bakes these paths in
    # verbatim, so taking the personal name here would build a generation
    # rooted at a home directory this user cannot even create.
    #
    # The git identity is untouched: features/cli/git reads vars.user, so
    # commits stay attributed to the personal name and email.
    username = "szn";
    homeDirectory = "/home/szn";

    # Short by design. `gh` and `gnumake` are terminal tools; the nerd font is
    # not optional because features/cli/ghostty pins `JetBrainsMono Nerd Font`
    # in its config, and a terminal without its glyphs is a broken terminal.
    # Anything graphical that used to sit here (obsidian) is gone.
    packages = with pkgs; [
      gh
      gnumake
      nerd-fonts.jetbrains-mono

      # Terminal tools that only ever lived inside ../../features/programs, which
      # is gated on hasDesktop, so dropping that tree stranded them. Listed
      # here rather than moved, to keep every other host's closure identical.
      k6
      vegeta
      postgresql # the psql client, not a server

      # Seazone's VPN. The one package here that also carries a window: the
      # nixpkgs derivation bundles pritunl-client (CLI), the electron app and
      # its .desktop entry, and they cannot be separated without an override
      # that would drift from upstream. Kept whole because the VPN is not
      # optional for work, and the extra launcher icon is a fair price.
      #
      # The CLI alone does not connect: it talks to pritunl-client-service,
      # which needs root. `szn-pritunl-setup` installs that system unit, and
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
  # It cannot live in vars: nalyx is a public repo, and the address is a
  # @seazone.com.br one, so putting it there publishes an employee address to
  # every fork, mirror and scraper, permanently. It also cannot be read from
  # sops at eval time, because programs.git renders user.email into a store
  # file while a sops secret is a runtime path, and this profile carries no
  # sops module at all.
  #
  # So git reads it from a file home-manager deliberately does not own.
  # Verified that the include lands after the [user] block in the generated
  # config, and git takes the last value, so this wins over vars.user.email.
  #
  # Write it once on the machine:
  #   printf '[user]\n\temail = %s\n' 'you@seazone.com.br' > ~/.config/git/identity
  #
  # Signing needs no override: the key path is the same ~/.ssh/id_ed25519 on
  # that host, it is simply the Seazone key material sitting at that path.
  programs.git.includes = [
    { path = "${config.home.homeDirectory}/.config/git/identity"; }
  ];

  # The include silently falling back to the personal address is the failure
  # mode worth shouting about: commits would be attributed to the wrong
  # identity in the company's repos and nobody notices for weeks.
  home.activation.checkGitIdentity = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -s "$HOME/.config/git/identity" ]; then
      echo "warning: ~/.config/git/identity is missing, so commits will use ${vars.user.email}"
      echo "         write the work address there, see home/profiles/szn/default.nix"
    fi
  '';

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
