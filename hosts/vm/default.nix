{
  vars,
  lib,
  ...
}:
let
  vm_name = "lab";
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core/default.nix
  ]
  ++ (lib.optional (vars.desktop == "gnome") ../../modules/desktop/gnome.nix)
  ++ (lib.optional (vars.desktop == "hyprland") ../../modules/desktop/hyprland.nix);

  networking.hostName = vm_name;

  home-manager.users.${vars.user.name} = import ../../home;

  services = {
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };
    qemuGuest.enable = true;
    spice-vdagentd.enable = true;
    displayManager.gdm.wayland = lib.mkForce false;
  };

  boot.loader = {
    systemd-boot.enable = lib.mkForce false;
    efi.canTouchEfiVariables = lib.mkForce false;
    grub = {
      enable = true;
      device = "/dev/sda";
      useOSProber = true;
    };
  };

  programs.nix-ld.enable = true;
  virtualisation.hypervGuest.enable = true;
  virtualisation.waydroid.enable = true;
  hardware.graphics.enable = true;

  home-manager.backupFileExtension = "backup-rev";
}
