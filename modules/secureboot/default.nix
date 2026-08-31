{
  pkgs,
  lib,
  lanzaboote,
  ...
}:

{
  imports = [ lanzaboote.nixosModules.lanzaboote ];
  boot = {
    # Lanzaboote installs its own signed copy of systemd-boot, so the stock
    # systemd-boot installer must stay off. mkForce because hosts enable it.
    loader.systemd-boot.enable = lib.mkForce false;
    loader.grub.enable = lib.mkForce false;

    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";

      # Every generation is a full UKI (kernel + initrd in one binary) on the
      # ESP, 100-150MB each. Tighter than the limit of 5 in modules/core
      # because that one only has to bound much smaller systemd-boot entries.
      configurationLimit = lib.mkDefault 3;

      autoGenerateKeys.enable = true;
      autoEnrollKeys = {
        enable = true;
        # Keeps the Microsoft CAs in db: Windows still boots under Secure Boot
        # (anti-cheat keeps working) and signed option ROMs stay valid.
        includeMicrosoftKeys = true;
      };
    };
  };

  environment.systemPackages = [ pkgs.sbctl ];
}
