{
  pkgs,
  lib,
  ...
}:
let
  # Sync only herdr's config.toml. Everything else in ~/.config/herdr is
  # per-machine runtime state (session history, logs, sockets) and must stay
  # local: "!config.toml" keeps that one file, "*" ignores the rest.
  stignore = pkgs.writeText "herdr-stignore" ''
    !config.toml
    *
  '';
in
{
  home.activation.herdrStignore = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ~/.config/herdr
    cp ${stignore} ~/.config/herdr/.stignore
  '';
}
