# Point-in-time history for `~/wrk`, pushed from WSL to the homelab.
#
# Syncthing already replicates `~/wrk` across wsl, desktop and laptop, but with
# `maxConflicts = 0` and no versioning, which is replication and not backup: a
# `rm -rf` or a bad `git reset` reaches every copy within seconds, and no older
# copy exists anywhere in the fleet. restic supplies the axis Syncthing has
# none of, time. The homelab is where it lands because it is always on and
# nobody works on it, so nothing there can propagate a mistake back.
#
# Public repo, so this file only offers the option surface. The repository
# password is a SOPS secret, so a private layer is what turns it on.
{
  vars,
  lib,
  config,
  ...
}:
let
  cfg = config.modules.services.restic.wrk;

  home = "/home/${vars.user.name}";

  # The same list the Syncthing `.stignore` is built from, imported rather than
  # repeated: an exclude that one tool honours and the other does not means the
  # backup silently carries the ~8 GB the sync skips, and the divergence is
  # invisible until the disk fills. See that file for why every pattern is a
  # bare name with no slash.
  #
  # Fed to `exclude` and not to `extraBackupArgs`, because the upstream module
  # already renders that list into a single `--exclude-file` through
  # `pkgs.writeText` (nixos/modules/services/backup/restic.nix:402-404), which
  # is the mechanism we wanted and keeps the two consumers visibly symmetric.
  excludes = import ../wrk-excludes.nix;

  # Shared by the two entries below. Two entries and not one because upstream
  # appends `forget --prune` to the backup service itself (restic.nix:409-412),
  # so a single entry can only prune on the backup's own schedule, and a daily
  # prune rewrites the repository index every day to reclaim nothing.
  common = {
    inherit (cfg) repository passwordFile;

    # Not root, which is the upstream default (restic.nix:198-205). Root on this
    # host has no SSH key, so the SFTP transport would fail before it ever
    # reached the repository, while the user's `~/.ssh/id_ed25519` is already
    # trusted by the homelab. That key is also the one whose ssh-to-age
    # derivation decrypts the SOPS secret holding the repository password, so a
    # single private key governs both reaching the repository and opening it.
    #
    # Which is also the limit of what this buys, verified 2026-09-08: sops-core
    # in the private repo puts that same personal key on every host including
    # the homelab, so the repository password is withheld from the far end by
    # deployment (never declared as a secret there) and not by cryptography.
    # What restic's own encryption still buys unconditionally is the data at
    # rest: a stolen disk, or that machine powered off, yields ciphertext.
    user = vars.user.name;
  };
in
{
  options.modules.services.restic.wrk = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Back `~/wrk` up to the homelab with restic, daily.

        Default false, and deliberately not enabled by any host in this repo:
        the repository password only exists as a SOPS secret in a private
        layer, and enabling this without `passwordFile` is an evaluation error
        by the assertion below. So the layer that owns the secret is the layer
        that turns this on, and a clone with no private input still evaluates.

        Meant for WSL alone. Syncthing converges every peer, so one backup
        source covers the whole fleet, and several writers against one restic
        repository would only fight over its lock.
      '';
    };

    repository = lib.mkOption {
      type = lib.types.str;
      default = "sftp:homelab:/data/backup/wrk";
      description = ''
        restic repository URL.

        SFTP over the tailnet by default: `homelab` resolves through Tailscale
        MagicDNS, and that host publishes no port to the internet, so the
        transport needs no tunnel of its own and no port forward.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/restic-wrk";
      description = ''
        Runtime path to a file holding the repository password, typically a
        sops-nix secret's `path`.

        A string rather than `lib.types.path`, for two reasons: the file only
        exists after activation, so there is nothing for the store to copy, and
        the upstream option this feeds is typed `nullOr str` too. Never a
        literal password, which would end up world-readable in /nix/store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.passwordFile != null;
        message = ''
          modules.services.restic.wrk is enabled with no passwordFile. Set it
          from the private layer that owns the secret, for example
          `modules.services.restic.wrk.passwordFile = config.sops.secrets."restic/wrk".path;`.
          An error and not a warning on purpose: a repository initialized with
          an empty password is a repository nobody can restore from, and that is
          only discovered on the day it is needed.
        '';
      }
    ];

    services.restic.backups = {
      wrk = common // {
        paths = [ "${home}/wrk" ];
        exclude = excludes;

        # The repository does not exist yet, and creating it by hand would make
        # the first run of a scheduled job depend on someone remembering a
        # manual step. Upstream guards this with `restic cat config || restic
        # init` (restic.nix:480-482), so it is a no-op once the repository is
        # there. The one way it bites: if the far side ever presents an empty
        # directory (the data disk failed to mount and the path exists on the
        # root filesystem instead), this initializes a second, empty repository
        # instead of failing. The homelab therefore creates that directory
        # declaratively on the data disk itself.
        initialize = true;

        # Nothing here tries to wake the homelab first. WoWLAN needs a magic
        # packet on the homelab's own LAN broadcast domain, and a Tailscale
        # packet will not do it, so a wake attempt from WSL would be a call that
        # looks like it works and never does. A run that cannot reach the host
        # fails, loudly, and `Persistent` catches it up when both ends are next
        # online at the same time. No `|| true` anywhere in this file for the
        # same reason: a backup that exits 0 having copied nothing is worse than
        # no backup at all.
        timerConfig = {
          OnCalendar = "*-*-* 02:00:00";
          Persistent = true;
        };
      };

      wrk-prune = common // {
        # No `paths` and no `command`, which upstream reads as a prune-only job
        # (restic.nix:140-142): this unit runs `unlock` then `forget --prune`
        # and never touches the source tree.
        pruneOpts = [
          "--keep-daily 7"
          "--keep-weekly 4"
          "--keep-monthly 6"
        ];

        timerConfig = {
          OnCalendar = "Mon 04:00:00";
          Persistent = true;
        };

        # `createWrapper` puts a `restic-<name>` script on PATH with the
        # repository and password already in the environment. One such entry
        # point is enough, and `restic-wrk` is the one to reach for; a second
        # wrapper pointing at the same repository is only ambiguity.
        createWrapper = false;
      };
    };

    # `forget --prune` takes an exclusive repository lock, so a prune running
    # next to a backup makes one of the two fail. The schedules above are two
    # hours apart, but `Persistent` means both can be due at once when WSL has
    # been off over a Monday, and systemd would then start them in the same
    # transaction. Ordering costs nothing and removes that false alarm.
    systemd.services.restic-backups-wrk-prune.after = [ "restic-backups-wrk.service" ];
  };
}
