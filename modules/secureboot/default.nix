{
  pkgs,
  lib,
  lanzaboote,
  ...
}:

{
  imports = [ lanzaboote.nixosModules.lanzaboote ];
  boot = {
    loader.systemd-boot.enable = lib.mkForce false;
    loader.grub.enable = false;

    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
  };

  environment.systemPackages = [ pkgs.sbctl ];
}
