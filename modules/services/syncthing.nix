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

  # This module is imported by wsl, desktop, laptop and homelab. WSL and desktop
  # send Claude Code and omp history; the laptop only receives it. The homelab
  # takes part in the `wrk` folder alone, and only as an untrusted device.
  isLaptop = config.networking.hostName == "laptop";
  isWsl = config.networking.hostName == "nixos-wsl";
  isHomelab = config.networking.hostName == "homelab";

  passwordFile = config.modules.services.syncthing.encryptionPasswordFile;

  # The three hosts that hold plaintext and the folder password.
  trustedPeers = [
    "laptop"
    "wsl"
    "desktop"
  ];

  # The homelab joins a folder only when a private layer supplied the password,
  # and never otherwise. A missing password must not degrade into an unencrypted
  # share: the first rebuild without the private layer would then push plaintext
  # work data onto the untrusted host, and pushing that cannot be undone. An
  # absent peer is the safe failure. The nixpkgs module reads this path at
  # activation time and injects it with jq before POSTing to the REST API, so
  # the password itself never reaches the Nix store.
  untrustedPeer = lib.optional (passwordFile != null) {
    name = "homelab";
    encryptionPasswordFile = passwordFile;
  };
in
{
  options.modules.services.syncthing.encryptionPasswordFile = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = ''
      Path to the file holding the Syncthing folder password, held by the
      trusted peers (wsl, desktop, laptop) and used to offer every folder to the
      homelab as a Receive Encrypted device.

      One password for all four folders rather than one each: the threat model
      is identical (the homelab must read none of them), and a second password
      would only add a way for them to drift apart.

      Null by default, and null means the homelab is not a peer of any folder:
      a missing password never degrades into an unencrypted share, because a
      single rebuild in that state would push plaintext onto an untrusted host,
      and pushing that cannot be undone.

      The homelab must never be a recipient of this secret. It holds only
      encrypted blocks, and reading the password there would make the untrusted
      device trusted again, which is the whole point of the arrangement.
    '';
  };

  config = {
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
          # Declared like its peers so the public flake still evaluates
          # standalone. The real id has to be re-collected on the machine with
          # `syncthing device-id`: Syncthing was removed from that host in
          # PR #104, so any id written down before then is stale.
          homelab.id = lib.mkDefault placeholderId;
        };

        # Single shared work folder. Plaintext and bidirectional on wsl, desktop
        # and laptop; encrypted at rest on the homelab.
        # maxConflicts = 0 -> last-writer-wins, no .sync-conflict files.
        # No versioning by design: point-in-time recovery is a separate restic
        # layer, not Syncthing's job.
        #
        # The homelab was deliberately removed from this folder in PR #104,
        # because it ran an AI agent and work data should not sit on an attack
        # surface. It comes back because the data stops being readable there:
        # `receiveencrypted` means the host never holds the folder password, so
        # it sees no filename, no content and no directory structure. That is
        # the durable half of the reversal, since it keeps holding even if an
        # agent lands on that host again later.
        folders.wrk = {
          id = "wrk";
          path =
            if isHomelab then
              # The 480 GB data disk, not $HOME: there is no plaintext ~/wrk on
              # this host to sync into. The directory is owned by
              # hosts/homelab/default.nix.
              "/data/sync/wrk-enc"
            else
              "/home/${vars.user.name}/wrk";
          # Bidirectional again on every trusted host. WSL was pinned to
          # receiveonly on 2026-08-10 because its rootfs had been reinstalled:
          # ~/wrk was empty while the local index still listed ~100k files, and
          # as sendreceive the first scan would have announced those as
          # deletions and wiped ~17.5 GB on the laptop.
          #
          # That reseed is done: ~/wrk was repopulated from the local restore and
          # the folder reached needFiles = 0 / errors = 0, so there is nothing
          # left to mistake for a deletion. Keeping it receiveonly now is
          # actively harmful, since it lets the peer's older copy overwrite work
          # done here.
          type = if isHomelab then "receiveencrypted" else "sendreceive";
          # Only the trusted peers carry `encryptionPasswordFile`, and they carry
          # it on the entry pointing AT the homelab. The homelab's own device
          # list is plain: it has no password for anyone.
          devices = trustedPeers ++ lib.optionals (!isHomelab) untrustedPeer;
          # The list omits the local device on the homelab, and that is correct,
          # not an oversight: Syncthing appends itself to every folder on config
          # load (ensureDevicePresent, called from FolderConfiguration.prepare
          # in lib/config/folderconfiguration.go).
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
        #
        # Guarded because the homelab imports this module for `wrk` alone. The
        # nixpkgs module filters folders only on `folder.enable` and POSTs every
        # other one, so an unguarded folder is created locally on every
        # importer.
        #
        # Bidirectional since 2026-09-10, where it used to be one-way into the
        # laptop. It is safe here specifically because of how Claude Code names
        # its files: every transcript is `<session-uuid>.jsonl` and every agent
        # record is `agent-<id>.meta.json`, so a given file has exactly one
        # author machine and two peers never write the same path. That is what
        # makes last-writer-wins harmless for this folder and not for the two
        # below it.
        folders.claude = {
          id = "claude";
          path = if isHomelab then "/data/sync/claude-enc" else "/home/${vars.user.name}/.claude/projects";
          type = if isHomelab then "receiveencrypted" else "sendreceive";
          devices = trustedPeers ++ lib.optionals (!isHomelab) untrustedPeer;
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
        #
        # Deliberately NOT made bidirectional when `claude` was, on 2026-09-10.
        # This folder carries agent.db plus its -wal and -shm sidecars, and
        # Syncthing treats those three as unrelated files, so it can deliver a
        # database from one instant with the write-ahead log from another. That
        # is corruption, not a conflict, and no `maxConflicts` setting addresses
        # it. One-way keeps the blast radius on the laptop, which is not the
        # machine being worked on; sendreceive would put a torn database on the
        # one that is. `AGENTS.md` and `RULES.md` in here are Nix-generated too
        # (see their .nix-sha256 companions), so writing them back would fight
        # activation.
        #
        # The homelab is still added: it only ever receives, so it changes
        # nothing about the one-way topology between the trusted peers.
        folders.omp = {
          id = "omp";
          path = if isHomelab then "/data/sync/omp-enc" else "/home/${vars.user.name}/.omp/agent";
          type =
            if isHomelab then
              "receiveencrypted"
            else if isLaptop then
              "receiveonly"
            else
              "sendonly";
          devices = trustedPeers ++ lib.optionals (!isHomelab) untrustedPeer;
          maxConflicts = 0;
        };

        # Herdr config plus session state, between WSL and the laptop, and
        # encrypted onto the homelab. Not defined on the desktop, which does not
        # run herdr. The .stignore written by home/features/cli/herdr keeps this
        # to config.toml, session.json and session-history.json: the logs are
        # 3.5 MB of per-machine noise and the two unix sockets must never be
        # replicated at all.
        #
        # Bidirectional as of 2026-09-10, so a session started on the laptop
        # comes back here. Unlike `claude`, the two state files have fixed
        # names, so this one really is last-writer-wins: herdr open on both
        # machines at once means one side's session-history.json overwrites the
        # other's. Accepted because the machines are used one at a time, and it
        # loses history rather than corrupting anything.
        folders.herdr = lib.mkIf (isLaptop || isWsl || isHomelab) {
          id = "herdr";
          path = if isHomelab then "/data/sync/herdr-enc" else "/home/${vars.user.name}/.config/herdr";
          type = if isHomelab then "receiveencrypted" else "sendreceive";
          devices = [
            "laptop"
            "wsl"
          ]
          ++ lib.optionals (!isHomelab) untrustedPeer;
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
  };
}
