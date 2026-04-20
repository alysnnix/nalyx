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
    ../../modules/services/syncthing.nix
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

  environment.systemPackages = with pkgs; [
    duperemove
    iw
    wakeonlan
  ];

  # WoWLAN: allow waking the homelab via WiFi magic packet
  systemd.services.wowlan = {
    description = "Enable Wake-on-WLAN";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iw}/bin/iw phy phy0 wowlan enable magic-packet";
    };
  };

  # Create Syncthing receive directories on btrfs
  systemd.tmpfiles.rules = [
    "d /data/sync/desktop 0755 ${vars.user.name} users -"
    "d /data/sync/laptop 0755 ${vars.user.name} users -"
    "d /data/sync/wsl 0755 ${vars.user.name} users -"
  ];

  # Weekly btrfs deduplication
  systemd.services.duperemove = {
    description = "Deduplicate /data/sync with duperemove";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.duperemove}/bin/duperemove -rd /data/sync";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.duperemove = {
    description = "Run duperemove weekly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };

  home-manager.users.${vars.user.name} = import ../../home;
  home-manager.backupFileExtension = "backup-homelab";
}
