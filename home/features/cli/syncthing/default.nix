{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Shared with restic, so an exclude honoured by one tool cannot silently drop
  # out of the other. The patterns and the measurements behind them live in
  # modules/wrk-excludes.nix.
  #
  # No `(?d)` prefix on purpose: ignoring must never delete an existing copy on
  # any peer.
  stignore = pkgs.writeText "wrk-stignore" (
    lib.concatMapStrings (pattern: "${pattern}\n") (import ../../../../modules/wrk-excludes.nix)
  );
in
{
  options.modules.cli.syncthing.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Write the ignore list for the shared `wrk` Syncthing folder.

      Default true because every host in the personal fleet is a peer. Set it
      false on a machine that must not bridge into that fleet at all, such as a
      managed work laptop, where the folder would otherwise be seeded with an
      ignore list for a sync that is never supposed to happen.
    '';
  };

  # Copied, not symlinked. `home.file."wrk/.stignore"` was lost the moment
  # Syncthing recreated ~/wrk after the 2026-08-10 WSL reinstall: the symlink
  # went away and the folder synced with no ignore list at all, pulling
  # node_modules into a 502k-file backlog. A real file written on every
  # activation survives the folder being recreated under it.
  #
  # `install` recreates the destination, which plain `cp` cannot do once the
  # previous copy exists as a read-only store copy.
  config.home.activation.wrkStignore = lib.mkIf config.modules.cli.syncthing.enable (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p ~/wrk
      $DRY_RUN_CMD install -m 0644 ${stignore} ~/wrk/.stignore
    ''
  );
}
