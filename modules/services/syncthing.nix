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
  # Claude Code and omp history; the laptop only receives it.
  isLaptop = config.networking.hostName == "laptop";
  isWsl = config.networking.hostName == "nixos-wsl";
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
        # WSL is receive-only until its wrk tree is re-seeded from the laptop.
        # Its rootfs was reinstalled on 2026-08-10, so ~/wrk is gone while the
        # local index still lists ~100k files. As sendreceive the first scan
        # would announce those as deletions and wipe ~17.5 GB on the laptop.
        # Receive-only never sends local changes, so the seed is safe: create
        # ~/wrk, then POST /rest/db/revert?folder=wrk to pull the global tree.
        # Flip back to sendreceive once needFiles hits 0 on WSL.
        type = if isWsl then "receiveonly" else "sendreceive";
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

      # omp harness history, mirroring folders.claude so a chat started on WSL
      # or the desktop can be resumed on the laptop. Syncs the whole agent
      # store: sessions/*.jsonl transcripts plus the SQLite index/state
      # (history.db, agent.db, models.db) and blobs/. Same one-way topology:
      # WSL and desktop send (sendonly), the laptop only receives
      # (receiveonly) and accumulates history from both.
      #
      # Caveat: the SQLite dbs are WAL and written live, so a mid-write sync
      # can land a torn db on the laptop; maxConflicts = 0 means last-writer
      # wins with no .sync-conflict copies. Accepted by design here.
      folders.omp = {
        id = "omp";
        path = "/home/${vars.user.name}/.omp/agent";
        type = if isLaptop then "receiveonly" else "sendonly";
        devices = [
          "laptop"
          "wsl"
          "desktop"
        ];
        maxConflicts = 0;
      };

      # Herdr config (config.toml): one-way WSL -> laptop only, so config set on
      # WSL follows to the laptop. sendonly on WSL, receiveonly on laptop; not
      # defined on desktop. A .stignore restricts the sync to config.toml, so
      # herdr's per-machine session history, logs and sockets stay local.
      folders.herdr = lib.mkIf (isLaptop || isWsl) {
        id = "herdr";
        path = "/home/${vars.user.name}/.config/herdr";
        type = if isLaptop then "receiveonly" else "sendonly";
        devices = [
          "laptop"
          "wsl"
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
