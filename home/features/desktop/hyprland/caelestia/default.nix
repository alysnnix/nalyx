{
  vars,
  lib,
  pkgs,
  ...
}:
let
  shellConfig = builtins.toJSON {
    background.visualiser.enabled = false;
    bar = { };
    dashboard.enabled = false;
    launcher.enableDangerousActions = true;
    lock = { };
    notifs = { };
    osd = {
      enabled = true;
      enableBrightness = true;
      enableMicrophone = true;
    };
    services = {
      weather.location = vars.weather.location;
      showLyrics = false;
    };
    session.enabled = true;
    sidebar.enabled = false;
    utilities.enabled = false;
  };
in
{
  programs.caelestia = {
    enable = true;
    cli.enable = true;
  };

  # Write shell.json as a real file (not symlink) so Caelestia can modify it at runtime
  home.activation.caelestiaSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p ~/.config/caelestia
        if [ ! -f ~/.config/caelestia/shell.json ] || [ -L ~/.config/caelestia/shell.json ]; then
          rm -f ~/.config/caelestia/shell.json
          cat > ~/.config/caelestia/shell.json << 'SHELLJSON'
    ${shellConfig}
    SHELLJSON
        fi
  '';
}
