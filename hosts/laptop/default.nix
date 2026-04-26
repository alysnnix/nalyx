{
  vars,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core/default.nix
    ../../modules/drivers/intel.nix
    ../../modules/services/syncthing.nix
    ../../modules/desktop/moonlight-kiosk.nix
  ]
  ++ (lib.optional (vars.desktop == "gnome") ../../modules/desktop/gnome.nix)
  ++ (lib.optional (vars.desktop == "hyprland") ../../modules/desktop/hyprland.nix);

  networking.hostName = "laptop";
  programs.kdeconnect.enable = true;
  modules.desktop.moonlight-kiosk.enable = true;
  home-manager.users.${vars.user.name} = import ../../home;
  home-manager.backupFileExtension = "backup-laptop";
}
