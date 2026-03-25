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
