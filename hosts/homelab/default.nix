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

  # One explicit key, matching every other host, instead of whatever the GitHub
  # account happens to publish.
  #
  # This used to fetch https://github.com/<user>.keys, which authorized EVERY
  # key on the account. That is fine while the account has one key and quietly
  # dangerous the moment it has two: adding a key for an employer-managed
  # laptop handed that laptop SSH into this box, and modules/services/hermes.nix
  # forwarded the same list to root inside the hermes guest. The pinned hash
  # breaking on the second key is what surfaced it.
  #
  # It was also an impure eval-time fetch, so a network hiccup or an upstream
  # change failed the build of a host that has nothing to do with GitHub.
  users.users.${vars.user.name}.openssh.authorizedKeys.keys = [ vars.user.publicKey ];

  environment.systemPackages = with pkgs; [
    btop
    iw
    wakeonlan
  ];

  # Backing dir for the encrypted `wrk` Syncthing folder and for the restic
  # repository WSL pushes over SFTP. Both live on the data disk, not $HOME.
  # The paths themselves are set in modules/services/syncthing.nix and on the
  # WSL side, so this host only has to own the directories.
  systemd.tmpfiles.rules = [
    "d /data/sync 0755 ${vars.user.name} users -"
    "d /data/sync/wrk-enc 0700 ${vars.user.name} users -"
    "d /data/backup 0755 ${vars.user.name} users -"
    "d /data/backup/wrk 0700 ${vars.user.name} users -"
  ];

  # No duperemove here, unlike the pre-#104 config. It deduplicated
  # /data/sync weekly, which is pointless once the contents are encrypted:
  # identical plaintext blocks encrypt to different ciphertext, so the scan
  # finds nothing and only burns CPU on a machine that is meant to idle.

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

  home-manager.users.${vars.user.name} = {
    imports = [ ../../home ];

    # This host holds the `wrk` folder encrypted, under /data/sync, and has no
    # plaintext ~/wrk at all. Writing an ignore list into a home directory that
    # never holds the folder would be pure noise, and ignores are honoured by
    # the sending side anyway.
    modules.cli.syncthing.enable = false;
  };
  home-manager.backupFileExtension = "backup-homelab";
}
