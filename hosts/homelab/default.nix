{
  vars,
  pkgs,
  config,
  lib,
  hasPrivate ? false,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core/default.nix
    ../../modules/services/openclaw.nix
  ];

  networking = {
    hostName = "homelab";

    # Zero public ports — only Tailscale can reach this machine
    firewall = {
      enable = true;
      allowedTCPPorts = [ ];
      allowedUDPPorts = [ ];
      trustedInterfaces = [ "tailscale0" ];
    };

    # WiFi — auto-connect to home network
    networkmanager.ensureProfiles = {
      environmentFiles = lib.mkIf hasPrivate [
        config.sops.templates."wifi-env".path
      ];
      profiles.home-wifi = {
        connection = {
          id = "Aly 5G";
          type = "wifi";
          autoconnect = true;
          autoconnect-priority = 100;
        };
        wifi = {
          ssid = "Aly 5G";
          mode = "infrastructure";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "$WIFI_PSK";
        };
      };
    };
  };

  # SOPS template: env file with WiFi password for NetworkManager
  sops.templates."wifi-env" = lib.mkIf hasPrivate {
    content = ''
      WIFI_PSK=${config.sops.placeholder.wifi_password}
    '';
  };

  # SSH access (only reachable via Tailscale due to firewall)
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # Avahi mDNS — publishes homelab.local on the network
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
    openFirewall = true;
  };

  users.users.${vars.user.name}.openssh.authorizedKeys.keyFiles = [
    (builtins.fetchurl {
      url = "https://github.com/${vars.user.social.github}.keys";
      sha256 = "134sxqhxsiphqz82l33vmalfabhi121404jg6ljs0n55c4svlq9l";
    })
  ];

  home-manager.users.${vars.user.name} = import ../../home;
  home-manager.backupFileExtension = "backup-homelab";
}
