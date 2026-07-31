{
  pkgs,
  lib,
  ...
}:
let
  # herdr keybindings: alt-based direct chords for workspace ("space") control.
  # up/down cycle spaces, alt+w closes the current one, alt+n creates a new one.
  configFile = pkgs.writeText "herdr-config.toml" ''
    [keys]
    previous_workspace = "alt+up"
    next_workspace = "alt+down"
    close_workspace = "alt+w"
    new_workspace = "alt+n"
  '';

  # herdr writes per-machine logs into ~/.config/herdr; keep them out of sync.
  stignore = pkgs.writeText "herdr-stignore" ''
    *.log
  '';
in
{
  home.activation.herdrConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ~/.config/herdr
    cp ${stignore} ~/.config/herdr/.stignore

    # Seed config.toml as a real file (not a nix symlink) so syncthing can own
    # it. Only writes when absent, so a version synced from another host stays.
    if [ ! -f ~/.config/herdr/config.toml ] || [ -L ~/.config/herdr/config.toml ]; then
      rm -f ~/.config/herdr/config.toml
      cp ${configFile} ~/.config/herdr/config.toml
      chmod u+w ~/.config/herdr/config.toml
    fi
  '';
}
