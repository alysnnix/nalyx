# Homelab host — server-only NixOS install, reachable only via Tailscale.
# Threat model and one-time bootstrap steps: see nalyx-private SECURITY.md.
{
  vars,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core/default.nix
    ../../modules/services/openclaw.nix
    ../../modules/services/syncthing.nix
    ../../modules/services/tailnet-proxy.nix
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

    # WiFi — configured via private module (SOPS template with WiFi password)
    networkmanager.ensureProfiles = {
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
    btop
    duperemove
    iw
    wakeonlan
  ];

  systemd = {
    # Syncthing receive directories on btrfs. Each folder MUST be marked
    # "Receive Only" in the Syncthing UI — see nalyx-private SECURITY.md.
    tmpfiles.rules = [
      "d /data/sync/desktop 0755 ${vars.user.name} users -"
      "d /data/sync/laptop 0755 ${vars.user.name} users -"
      "d /data/sync/wsl 0755 ${vars.user.name} users -"
    ];

    services = {
      # WoWLAN: allow waking the homelab via WiFi magic packet
      wowlan = {
        description = "Enable Wake-on-WLAN";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.iw}/bin/iw phy phy0 wowlan enable magic-packet";
        };
      };

      # Weekly btrfs deduplication
      duperemove = {
        description = "Deduplicate /data/sync with duperemove";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.duperemove}/bin/duperemove -rd /data/sync";
          Nice = 19;
          IOSchedulingClass = "idle";
        };
      };
    };

    timers.duperemove = {
      description = "Run duperemove weekly";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };
  };

  home-manager.users.${vars.user.name} = import ../../home;
  home-manager.backupFileExtension = "backup-homelab";
}
