{ pkgs, ... }:

{
  programs.zed-editor = {
    enable = true;
    package = pkgs.zed-editor;

    extensions = [
      "nix"
      "toml"
      "catppuccin"
    ];

    userSettings = {
      vim_mode = false;
      ui_font_size = 16;
      buffer_font_size = 16;

      theme = {
        mode = "system";
        light = "One Light";
        dark = "One Dark";
      };

      project_panel = {
        folder_icons = false;
      };

      buffer_font_family = "JetBrainsMono Nerd Font";
      ui_font_family = "JetBrainsMono Nerd Font";

      relative_line_numbers = true;
      autosave = "on_focus_change";

      format_on_save = "on";
      tab_size = 2;

      agent = {
        default_model = {
          provider = "anthropic";
          model = "claude-opus-4-6";
        };
        version = "2";
      };

      terminal = {
        font_family = "JetBrainsMono Nerd Font";
        font_size = 15;
        shell = "system";
      };

      languages = {
        JavaScript = {
          code_actions_on_format = {
            source.fixAll.eslint = true;
          };
        };

        nix = {
          tab_size = 2;
          language_servers = [
            "nixd"
            "nil"
          ];
        };
      };
    };

    userKeymaps = [
      {
        context = "Workspace";
        bindings = {
          "alt-1" = "project_panel::ToggleFocus";
          "alt-2" = "git_panel::ToggleFocus";
          "alt-q" = "workspace::ToggleBottomDock";
          "ctrl-shift-t" = "workspace::NewCenterTerminal";
          "alt-n" = "workspace::NewFile";
          "ctrl-e" = "file_finder::Toggle";
          "ctrl-r" = "projects::OpenRecent";
        };
      }
      {
        bindings = {
          "alt-1" = "project_panel::ToggleFocus";
          "alt-2" = "git_panel::ToggleFocus";
        };
      }
      {
        context = "ProjectPanel";
        bindings = {
          "alt-n" = "project_panel::NewFile";
          "alt-shift-n" = "project_panel::NewDirectory";
        };
      }
      {
        context = "Editor && vim_mode == normal";
        bindings = {
          "space q" = "pane::CloseActiveItem";
          "shift-k" = "editor::Hover";
        };
      }
    ];
  };
}
