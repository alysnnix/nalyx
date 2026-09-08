# Rebuildable paths inside `~/wrk`, excluded from both Syncthing and restic.
#
# A plain list rather than a module option, because the two consumers live in
# different module systems and cannot share one: `home/features/cli/syncthing`
# is a home-manager module (and is also evaluated by the standalone `wrk`
# profile, which has no `osConfig`), while `modules/services/restic.nix` is a
# NixOS module. A data file both can `import` is the only thing that keeps the
# list in one place.
#
# Keeping it in one place is the point: an exclude that Syncthing honours and
# restic does not means the backup silently carries ~8 GB of node_modules,
# and the divergence is invisible until the disk fills.
#
# Measured on the 2026-08-10 laptop snapshot (809583 entries), counting only
# what each pattern adds on top of the ones above it:
#
#   node_modules   251413 entries   2.56 GB
#   .pnpm-store    262754 entries   2.99 GB   (more entries than node_modules)
#   .docker           497 entries
#   __pycache__           0          kept as a guard
#
# Re-measured on WSL 2026-09-08: `~/wrk` is 17 GB, and 8.8 GB with these four
# excluded, so they are roughly half the payload.
#
# `.docker` earns its place for a second reason beyond size: it holds container
# volume data owned by root (postgres data dirs), which Syncthing running as
# the user cannot read, and which corrupts if synced mid-write. That was the
# "failed items" plus watcher errors seen on the initial seed in PR #104.
#
# Deliberately NOT excluded, despite being large:
#   .worktrees   109040 entries / 1.31 GB, but these are real git worktrees
#                with code being worked on, not rebuildable artifacts
#   build          6212 entries / 0.54 GB, and `build` is too generic a name
#                to match blindly (some projects keep sources under build/)
#
# Measured at zero marginal hits, so absent on purpose: .cache, .next, dist,
# target, .venv, .direnv, .devenv, .terraform, *.tmp, vendor.
#
# Every pattern here is a bare name with no slash, which both tools match at
# any depth (Syncthing matches a slashless pattern at any level; restic matches
# it against the basename). So one list is literally correct for both, and a
# pattern with a slash would NOT be, since the two syntaxes diverge there.
[
  "node_modules"
  ".pnpm-store"
  "__pycache__"
  ".docker"
]
