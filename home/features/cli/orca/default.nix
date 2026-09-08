{
  pkgs,
  lib,
  config,
  ...
}:
# Orca (https://www.onorca.dev), the front end for the coding agents this
# config already installs.
#
# Nothing here installs Orca, on purpose. It is a graphical app, so it comes
# from the platform's package manager: the `.deb` on a managed laptop, for the
# reason home/profiles/wrk spells out (an osquery agent inventories
# deb_packages and never /nix/store), and the Windows installer when the GUI
# lives on Windows and only reaches a NixOS host over SSH. There is also no
# derivation to reuse: `orca` in nixpkgs is the GNOME screen reader, which is
# why upstream named the Linux binary `orca-ide` in the first place.
#
# What this file does own is the one thing the platform gets wrong. A GNOME
# Wayland session never sources ~/.profile, so an Orca started from the
# application grid comes up with no nix profile on PATH and finds none of the
# agents it exists to orchestrate. The desktop entry below shadows the one
# from the `.deb` and routes the binary through a login shell, which is where
# .zshenv sources hm-session-vars.sh, and with targets.genericLinux that file
# is where nix.sh lands (see ../zsh, same reasoning as the bash handoff).
#
# Deliberately not done by exporting PATH for the whole session through
# ~/.config/environment.d/: that changes the environment every GUI process
# inherits in order to fix one app.
let
  # Wrapped in a script rather than inlined into Exec because the desktop entry
  # spec makes the inline version a minefield: single quotes are literal
  # characters there, `$` has to be backslash-escaped inside double quotes, and
  # field codes like %U are not allowed inside a quoted argument at all. A
  # store path plus a bare %U sidesteps all three, and shellcheck gets to run
  # on the script at build time.
  #
  # /opt/Orca/orca-ide, absolute, is what upstream's own entry execs. Going
  # through PATH instead would depend on the symlink the postinst drops in
  # /usr/bin, which is not part of the package's file list.
  orcaSession = pkgs.writeShellApplication {
    name = "orca-ide-session";
    text = ''
      # shellcheck disable=SC2016 # $@ is for the inner zsh, not this shell
      exec ${lib.getExe config.programs.zsh.package} -l -c \
        'exec /opt/Orca/orca-ide "$@"' orca-ide "$@"
    '';
  };

  # Built with makeDesktopItem rather than written by hand so
  # desktop-file-validate runs at build time. Fields are copied from the file
  # upstream ships, so the launcher entry stays the one they designed, with
  # Exec as the single difference. startupWMClass is among them because without
  # it the window never associates with the icon that launched it. Their
  # MimeType lists x-scheme-handler/orca twice; not reproduced.
  orcaEntry = pkgs.makeDesktopItem {
    name = "orca-ide";
    desktopName = "Orca";
    comment = "Next-gen IDE for parallel agentic development";
    exec = "${lib.getExe orcaSession} %U";
    icon = "orca-ide";
    terminal = false;
    type = "Application";
    categories = [ "Utility" ];
    mimeTypes = [
      "text/markdown"
      "x-scheme-handler/orca"
    ];
    startupWMClass = "orca";
  };
in
{
  options.modules.cli.orca.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Shadow the Orca desktop entry so a graphically launched Orca inherits the
      nix userland, which is where the coding agents it drives live.

      Assumes Orca was installed from the upstream `.deb`, whose own entry
      execs /opt/Orca/orca-ide.

      Default false because it is only needed where Orca is installed by the
      distro and started from a desktop session. A NixOS host that merely
      serves Orca over SSH needs nothing: sshd hands every command a full
      environment already, since /etc/zshenv sources set-environment for
      non-interactive shells too.
    '';
  };

  # Into xdg.dataFile, not xdg.desktopEntries. That option installs the entry as
  # a package, so it lands in ~/.nix-profile/share/applications, which a desktop
  # session only scans if its own XDG_DATA_DIRS names it, and the session
  # environment is precisely the one that knows nothing about nix here. The
  # basename has to match upstream's exactly: $XDG_DATA_HOME/applications is
  # searched first by spec, so an identical name shadows /usr/share instead of
  # adding a second Orca to the grid.
  config.xdg.dataFile."applications/orca-ide.desktop" = lib.mkIf config.modules.cli.orca.enable {
    source = "${orcaEntry}/share/applications/orca-ide.desktop";
  };
}
