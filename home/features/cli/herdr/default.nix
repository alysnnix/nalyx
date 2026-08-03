{
  pkgs,
  lib,
  ...
}:
let
  tomlFormat = pkgs.formats.toml { };

  # Utility panes bound to keys below. Each is a self-contained script with its
  # tools pinned from nixpkgs (no reliance on the pane's PATH). They open as a
  # zoomed pane in the current directory; close the pane to return.
  clockApp = pkgs.writeShellApplication {
    name = "herdr-clock";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      while true; do
        printf '\033[2J\033[H'
        date '+  %A, %d %B %Y'
        date '+  %H:%M:%S %Z'
        sleep 1
      done
    '';
  };

  gitStatusApp = pkgs.writeShellApplication {
    name = "herdr-gitstatus";
    runtimeInputs = [
      pkgs.git
      pkgs.coreutils
    ];
    text = ''
      while true; do
        printf '\033[2J\033[H'
        (
          if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            printf '# %s\n\n' "$(basename "$PWD")"
            git -c color.ui=always status -sb
            printf '\n-- recent --\n'
            git -c color.ui=always log --oneline -10 --decorate
          else
            printf 'not a git repository: %s\n' "$PWD"
          fi
        ) 2>&1 || true
        sleep 3
      done
    '';
  };

  # Weather auto-detects the location by IP (wttr.in). Change the URL to pin a
  # city, e.g. https://wttr.in/Florianopolis
  weatherApp = pkgs.writeShellApplication {
    name = "herdr-weather";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      while true; do
        printf '\033[2J\033[H'
        curl -fsS --max-time 15 'https://wttr.in/?F' 2>&1 || printf 'weather unavailable\n'
        sleep 900
      done
    '';
  };

  # Declarative herdr config. This file is the source of truth; edit it here,
  # not in ~/.config/herdr/config.toml (that copy is overwritten on switch).
  configToml = tomlFormat.generate "herdr-config.toml" {
    ui = {
      show_agent_labels_on_pane_borders = true;
      agent_panel_sort = "spaces";

      # Selecting with the mouse only marks text; copy happens on Ctrl+C.
      copy_on_select = false;

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
      close_pane = "alt+w"; # close the selected pane
      new_workspace = "alt+n";
      previous_tab = "alt+left";
      next_tab = "alt+right";
      split_vertical = "alt+d"; # split right (side by side) in the current pane
      close_tab = "shift+alt+w"; # close the current tab

      # Utility panes: open a zoomed pane in the current dir; close it to return.
      command = [
        {
          key = "alt+t";
          type = "pane";
          command = lib.getExe clockApp;
          description = "Clock";
        }
        {
          key = "alt+g";
          type = "pane";
          command = lib.getExe gitStatusApp;
          description = "Git status";
        }
        {
          key = "alt+c";
          type = "pane";
          command = lib.getExe weatherApp;
          description = "Weather";
        }
      ];
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
