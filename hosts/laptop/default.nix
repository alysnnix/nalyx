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
  ]
  ++ (lib.optional (vars.desktop == "gnome") ../../modules/desktop/gnome.nix)
  ++ (lib.optional (vars.desktop == "hyprland") ../../modules/desktop/hyprland.nix);

  networking.hostName = "laptop";
  programs.kdeconnect.enable = true;
  home-manager.users.${vars.user.name} = import ../../home;
}
