{
  vars,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core/default.nix
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

  users.users.${vars.user.name}.openssh.authorizedKeys.keys = [
    vars.user.publicKey
  ];

  home-manager.users.${vars.user.name} = import ../../home;
  home-manager.backupFileExtension = "backup-homelab";
}
