{
  vars,
  lib,
  pkgs,
  ...
}:

{
  options.modules.desktop.gnome = {
    enable = lib.mkEnableOption "Enable GNOME at the System Level";
  };

  config = lib.mkIf (vars.desktop == "gnome") {
    programs.noisetorch.enable = true;
    services = {
      pipewire = {
        enable = true;
        pulse.enable = true;
      };

      xserver.enable = true;
      displayManager.gdm = {
        enable = true;
        wayland = true;
      };
      desktopManager.gnome.enable = true;
    };

    environment.variables.GDK_GL = "gles";
    environment.systemPackages = with pkgs; [
      gnome-extensions-cli
      gnomeExtensions.appindicator
      gnomeExtensions.just-perfection
      gnomeExtensions.dash-to-dock
      gnomeExtensions.rounded-window-corners-reborn
      gnomeExtensions.vitals
      lm_sensors
      nvtopPackages.full
      bottom
      liquidctl
      gnomeExtensions.unite
    ];
  };
}
