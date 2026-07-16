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

  # This module is imported by wsl, desktop and laptop. WSL and desktop send
  # Claude history; the laptop only receives it.
  isLaptop = config.networking.hostName == "laptop";
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
        desktop.id = lib.mkDefault placeholderId;
      };

      # Single shared work folder, identical on wsl, desktop and laptop.
      # maxConflicts = 0 -> last-writer-wins, no .sync-conflict files.
      # No versioning by design.
      folders.wrk = {
        id = "wrk";
        path = "/home/${vars.user.name}/wrk";
        type = "sendreceive";
        devices = [
          "laptop"
          "wsl"
          "desktop"
        ];
        maxConflicts = 0;
        # More parallel writes on the receiving side speeds up the initial
        # seed of many small files (the git repos). Default is 2.
        maxConcurrentWrites = 8;
      };

      # Claude Code conversation transcripts, so a chat started on WSL or the
      # desktop can be resumed on the laptop. Only projects/ is synced (the
      # resumable .jsonl session logs); credentials, caches and Nix-managed
      # config files under .claude are left out. Resume matches by cwd path,
      # which is identical on all hosts (/home/aly/...).
      #
      # Sync is one-way: WSL and desktop send (sendonly), the laptop only
      # receives (receiveonly) and accumulates history from both. The two
      # senders never accept remote changes, so they don't exchange history
      # with each other and Claude activity on the laptop never propagates
      # back.
      folders.claude = {
        id = "claude";
        path = "/home/${vars.user.name}/.claude/projects";
        type = if isLaptop then "receiveonly" else "sendonly";
        devices = [
          "laptop"
          "wsl"
          "desktop"
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
