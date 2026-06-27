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

  # SSH só acessível via Tailscale: porta 22 fechada nas demais interfaces
  # (WiFi/ethernet) já que o notebook fica em redes não confiáveis.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };
  users.users.${vars.user.name}.openssh.authorizedKeys.keys = [ vars.user.publicKey ];

  programs.kdeconnect.enable = true;
  modules.desktop.moonlight-kiosk.enable = true;
  home-manager.users.${vars.user.name} = import ../../home;
  home-manager.backupFileExtension = "backup-laptop";
}
