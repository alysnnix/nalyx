{ pkgs, lib, ... }:
let
  # Ignore list for the shared `wrk` Syncthing folder. Patterns without a
  # leading slash match at any depth, so a bare `node_modules` covers every
  # nested one.
  #
  # Measured on the 2026-08-10 laptop snapshot (809583 entries), counting only
  # what each pattern adds on top of the ones above it:
  #
  #   node_modules   251413 entries   2.56 GB
  #   .pnpm-store    262754 entries   2.99 GB   (more entries than node_modules)
  #   .docker           497 entries
  #   __pycache__           0          kept as a guard
  #
  # Together these drop roughly 64% of the tree from the index.
  #
  # Deliberately NOT ignored, despite being large:
  #   .worktrees   109040 entries / 1.31 GB, but these are real git worktrees
  #                with code being worked on, not rebuildable artifacts
  #   build          6212 entries / 0.54 GB, and `build` is too generic a name
  #                to match blindly (some projects keep sources under build/)
  #
  # Measured at zero marginal hits, so absent on purpose: .cache, .next, dist,
  # target, .venv, .direnv, .devenv, .terraform, *.tmp, vendor.
  #
  # Everything listed is rebuilt locally and carries host-specific paths (native
  # bindings, nix store references), so syncing it breaks the project on the
  # receiving host instead of saving work. No `(?d)` prefix on purpose: ignoring
  # must never delete an existing copy on any peer.
  stignore = pkgs.writeText "wrk-stignore" ''
    node_modules
    .pnpm-store
    __pycache__
    .docker
  '';
in
{
  # Copied, not symlinked. `home.file."wrk/.stignore"` was lost the moment
  # Syncthing recreated ~/wrk after the 2026-08-10 WSL reinstall: the symlink
  # went away and the folder synced with no ignore list at all, pulling
  # node_modules into a 502k-file backlog. A real file written on every
  # activation survives the folder being recreated under it.
  #
  # `install` recreates the destination, which plain `cp` cannot do once the
  # previous copy exists as a read-only store copy.
  home.activation.wrkStignore = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p ~/wrk
    $DRY_RUN_CMD install -m 0644 ${stignore} ~/wrk/.stignore
  '';
}
