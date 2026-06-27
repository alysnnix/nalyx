{
  vars,
  lib,
  config,
  ...
}:
let
  # Real device ids live in the private repo (nixos/syncthing.nix) and
  # override these placeholders. The placeholder keeps the public flake
  # evaluable on its own (CI / no private repo); it never connects.
  placeholderId = "AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA";
in
{
  services.syncthing = {
    enable = true;
    user = vars.user.name;
    group = "users";
    dataDir = "/home/${vars.user.name}";
    configDir = "/home/${vars.user.name}/.config/syncthing";
    overrideDevices = true;
    overrideFolders = true;

    settings = {
      # Traffic is pinned 100% to Tailscale: no public relays, no global or
      # local discovery, no NAT traversal. Peers are dialed only by their
      # Tailscale addresses (set in the private repo). If Tailscale is down,
      # sync waits for it to come back (fail-closed).
      options = {
        relaysEnabled = false;
        globalAnnounceEnabled = false;
        localAnnounceEnabled = false;
        natEnabled = false;
        listenAddresses = [
          "tcp://0.0.0.0:22000"
          "quic://0.0.0.0:22000"
        ];
      };

      devices = {
        laptop.id = lib.mkDefault placeholderId;
        wsl.id = lib.mkDefault placeholderId;
        homelab.id = lib.mkDefault placeholderId;
      };

      # Single shared work folder, identical on every host (path differs:
      # homelab uses its data disk, work hosts use $HOME).
      # maxConflicts = 0 -> last-writer-wins, no .sync-conflict files.
      # No versioning by design (limited homelab storage).
      folders.wrk = {
        id = "wrk";
        # Homelab keeps the shared folder on its data disk; work hosts in $HOME.
        path =
          if config.networking.hostName == "homelab" then "/data/sync/wrk" else "/home/${vars.user.name}/wrk";
        type = "sendreceive";
        devices = [
          "laptop"
          "wsl"
          "homelab"
        ];
        maxConflicts = 0;
      };
    };
  };

  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [
      8384
      22000
    ];
    allowedUDPPorts = [
      22000
    ];
  };
}
