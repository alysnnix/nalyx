{ pkgs, vars, ... }:
{
  services.syncthing = {
    enable = true;
    user = vars.user.name;
    group = "users";
    dataDir = "/home/${vars.user.name}";
    configDir = "/home/${vars.user.name}/.config/syncthing";
    overrideDevices = false;
    overrideFolders = false;
  };

  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      8384
      22000
    ];
    allowedUDPPorts = [
      22000
      21027
    ];
  };
}
