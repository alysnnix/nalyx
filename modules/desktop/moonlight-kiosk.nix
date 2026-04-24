{
  pkgs,
  lib,
  vars,
  config,
  ...
}:

let
  cfg = config.modules.desktop.moonlight-kiosk;

  overridePath = "/etc/sddm.conf.d/99-moonlight-mode.conf";
  teeBin = "${pkgs.coreutils}/bin/tee";
  rmBin = "${pkgs.coreutils}/bin/rm";
  systemctlBin = "${pkgs.systemd}/bin/systemctl";

  kioskLauncher = pkgs.writeShellApplication {
    name = "moonlight-kiosk";
    runtimeInputs = [
      pkgs.cage
      pkgs.moonlight-qt
      pkgs.sudo
      pkgs.coreutils
    ];
    text = ''
      cleanup() {
        sudo ${rmBin} -f ${overridePath} || true
      }
      trap cleanup EXIT
      cage -s -- moonlight-qt
    '';
  };

  switchToMoonlight = pkgs.writeShellApplication {
    name = "moonlight-mode";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.sudo
    ];
    text = ''
      printf '[Autologin]\nSession=moonlight-kiosk\n' \
        | sudo ${teeBin} ${overridePath} > /dev/null
      exec sudo ${systemctlBin} restart display-manager
    '';
  };

  switchToHyprland = pkgs.writeShellApplication {
    name = "hyprland-mode";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.sudo
    ];
    text = ''
      sudo ${rmBin} -f ${overridePath}
      exec sudo ${systemctlBin} restart display-manager
    '';
  };

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
      switchToMoonlight
      switchToHyprland
    ];

    services.displayManager.sessionPackages = [ kioskSession ];

    systemd.tmpfiles.rules = [
      "d /etc/sddm.conf.d 0755 root root -"
    ];

    security.sudo.extraRules = [
      {
        users = [ vars.user.name ];
        commands = [
          {
            command = "${teeBin} ${overridePath}";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${rmBin} -f ${overridePath}";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${systemctlBin} restart display-manager";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
