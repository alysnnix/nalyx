{
  config,
  lib,
  vars,
  ...
}:

{
  options.modules.desktop.hyprland = {
    enable = lib.mkEnableOption "Enable Hyprland at the System Level";
  };

  config = lib.mkIf (vars.desktop == "hyprland") {
    programs.hyprland.enable = true;
    programs.hyprland.xwayland.enable = true;

    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;

      autoNumlock = true;
      settings = {
        Autologin = {
          Session = "hyprland";
          User = vars.user.name;
        };
      };
    };

    services.upower.enable = true;

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };
  };
}
