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
    # Importado sem `modules.services.paseo.enable`, ou seja so para DECLARAR
    # as opcoes. Este host nao roda o daemon, mas recebe `wrkNixosModules`
    # como todo host nao-servidor (flake.nix), e uma camada de projeto que
    # ensine um nome ao ditado (`modules.services.paseo.dictationVocabulary`)
    # ou declare um plugin (`services.paseo.settings.plugins`) derrubava a
    # avaliacao deste host inteiro com "The option `modules.services' does not
    # exist". Mesmo motivo escrito em home/features/cli/wrk.nix para o lado
    # home-manager: a opcao se declara onde o host a alcanca, nao so onde ela
    # e consumida.
    ../../modules/services/paseo.nix
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
