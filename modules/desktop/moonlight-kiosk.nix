{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.modules.desktop.moonlight-kiosk;

  kioskLauncher = pkgs.writeShellScriptBin "moonlight-kiosk" ''
    exec ${pkgs.cage}/bin/cage -s -- ${pkgs.moonlight-qt}/bin/moonlight
  '';

  kioskSession =
    (pkgs.writeTextFile {
      name = "moonlight-kiosk-session";
      destination = "/share/wayland-sessions/moonlight-kiosk.desktop";
      text = ''
        [Desktop Entry]
        Name=Moonlight Kiosk
        Comment=Moonlight fullscreen for remote streaming over Tailscale
        Exec=${kioskLauncher}/bin/moonlight-kiosk
        Type=Application
        DesktopNames=moonlight-kiosk
      '';
    }).overrideAttrs
      (_: {
        passthru.providedSessions = [ "moonlight-kiosk" ];
      });
in
{
  options.modules.desktop.moonlight-kiosk = {
    enable = lib.mkEnableOption "Minimal Wayland session that runs only Moonlight fullscreen";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.moonlight-qt
      pkgs.cage
      kioskLauncher
    ];

    services.displayManager.sessionPackages = [ kioskSession ];
  };
}
