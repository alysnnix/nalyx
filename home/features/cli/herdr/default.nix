{
  pkgs,
  lib,
  ...
}:
let
  tomlFormat = pkgs.formats.toml { };

  # Declarative herdr config. This file is the source of truth; edit it here,
  # not in ~/.config/herdr/config.toml (that copy is overwritten on switch).
  configToml = tomlFormat.generate "herdr-config.toml" {
    ui = {
      show_agent_labels_on_pane_borders = true;
      agent_panel_sort = "spaces";

      # Agent panel: show each agent's chat title (terminal title) instead of
      # the workspace folder name, which is identical for every agent in one repo.
      sidebar.agents.rows = [
        [
          "state_icon"
          "terminal_title_stripped"
          "tab"
        ]
        [ "agent" ]
      ];
    };

    experimental.pane_history = true;

    theme = {
      name = "catppuccin";
      auto_switch = false;
    };

    keys = {
      previous_workspace = "alt+up";
      next_workspace = "alt+down";
      close_workspace = "alt+w";
      new_workspace = "alt+n";
      previous_tab = "alt+left";
      next_tab = "alt+right";
      split_vertical = "alt+d"; # split right (side by side) in the current pane
      close_tab = "shift+alt+w"; # close the current tab
    };
  };

  # Sync only herdr's config.toml. Everything else in ~/.config/herdr is
  # per-machine runtime state (session history, logs, sockets) and must stay
  # local: "!config.toml" keeps that one file, "*" ignores the rest.
  stignore = pkgs.writeText "herdr-stignore" ''
    !config.toml
    *
  '';
in
{
  # Copy (not symlink) both files so they stay real, writable files that
  # syncthing can sync. `install` recreates the destination, which plain `cp`
  # cannot do once the previous copy exists as a read-only store copy.
  home.activation.herdr = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p ~/.config/herdr
    $DRY_RUN_CMD install -m 0644 ${configToml} ~/.config/herdr/config.toml
    $DRY_RUN_CMD install -m 0644 ${stignore} ~/.config/herdr/.stignore
  '';
}
