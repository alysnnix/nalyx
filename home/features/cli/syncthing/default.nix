{ ... }:
{
  # Ignore list for the shared `wrk` Syncthing folder. Patterns without a
  # leading slash match at any depth, so a bare `node_modules` covers every
  # nested one (verified against the folder index: the counts below match
  # Syncthing's own ignored tally exactly).
  #
  # Measured on the laptop's index (711848 files / 26.5 GB), only three of the
  # thirteen patterns this list used to carry ever matched anything:
  #
  #   node_modules   206068 files   1.95 GB   (29% of the tree, 7% of the bytes)
  #   .docker          3189 files   0.09 GB
  #   vendor            284 files   0.00 GB   (dropped, negligible)
  #
  # .cache, .next, target, dist, .venv, .direnv, .devenv, .terraform and *.tmp
  # matched zero files outside node_modules, so they are gone as dead weight.
  # __pycache__ also matches nothing today and is kept only as a guard.
  #
  # These are rebuilt locally and carry host-specific paths (native bindings,
  # nix store references), so syncing them breaks the project on the receiving
  # host instead of saving work. No `(?d)` prefix on purpose: ignoring must
  # never delete an existing copy on any peer.
  home.file."wrk/.stignore".text = ''
    node_modules
    __pycache__
    .docker
  '';
}
