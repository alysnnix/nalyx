{
  vars,
  lib,
  ...
}:

{
  imports = [
    # ../../modules/secureboot
    ./hardware-configuration.nix
    ../../modules/core/default.nix
    ../../modules/drivers/nvidia.nix
    ../../modules/services/nordvpn.nix
    ../../modules/services/syncthing.nix
  ]
  ++ (lib.optional (vars.desktop == "gnome") ../../modules/desktop/gnome.nix)
  ++ (lib.optional (vars.desktop == "hyprland") ../../modules/desktop/hyprland.nix);

  boot.loader = {
    timeout = lib.mkForce 30;
    systemd-boot.enable = lib.mkForce false;
    efi.canTouchEfiVariables = true;
    limine.secureBoot.enable = true;

    grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      useOSProber = true;
      configurationLimit = 10;
      extraEntries = ''
        menuentry "UEFI Firmware Settings" {
          fwsetup
        }
      '';
    };
  };

  security.pam.loginLimits = [
    {
      domain = "*";
      item = "nofile";
      type = "soft";
      value = "65535";
    }
    {
      domain = "*";
      item = "nofile";
      type = "hard";
      value = "65535";
    }
  ];

  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      gamescopeSession.enable = true;
    };
    gamemode.enable = true;
    gamescope.enable = true;
  };

  boot.kernelModules = [ "wireguard" ];

  networking.hostName = "desktop";

  # SSH só acessível via Tailscale: porta 22 fechada nas demais interfaces,
  # mesmo padrão do laptop e do wsl.
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

  home-manager.users.${vars.user.name} = import ../../home;
  home-manager.backupFileExtension = "backup-rev";
}
