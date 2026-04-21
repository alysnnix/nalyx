{
  config,
  lib,
  pkgs,
  vars,
  ...
}:

{
  imports = [
    ./matugen
  ]
  ++ (lib.optional (vars.shell == "caelestia") ./caelestia)
  ++ (lib.optionals (vars.shell == "waybar") [
    ./waybar
    ./rofi
  ]);

  options.modules.desktop.hyprland = {
    enable = lib.mkEnableOption "Habilita o ambiente Hyprland";
  };

  config = lib.mkIf (vars.desktop == "hyprland") {
    home.packages = with pkgs; [
      swww
      wl-clipboard
      grim
      slurp
      pamixer
      brightnessctl
      playerctl
      nautilus
      thunderbird
      qalculate-gtk
      nwg-look
      btop
      blueman
      networkmanagerapplet
    ];

    # Ensure colors.conf exists before Hyprland starts (Matugen generates it later)
    home.activation.ensureMatugenFiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p ~/.config/hypr ~/.config/kitty
      [ -f ~/.config/hypr/colors.conf ] || touch ~/.config/hypr/colors.conf
      [ -f ~/.config/kitty/colors.conf ] || touch ~/.config/kitty/colors.conf
    '';

    services.dunst = lib.mkIf (vars.shell == "waybar") {
      enable = true;
      settings = {
        global = {
          width = 350;
          height = 150;
          offset = "10x10";
          origin = "top-right";
          transparency = 0;
          frame_color = "#89b4fa";
          frame_width = 2;
          corner_radius = 12;
          font = "JetBrainsMono Nerd Font 10";
          padding = 12;
          horizontal_padding = 16;
          icon_position = "left";
          max_icon_size = 48;
          separator_color = "frame";
          gap_size = 6;
        };
        urgency_low = {
          background = "#1e1e2e";
          foreground = "#cdd6f4";
          frame_color = "#45475a";
          timeout = 5;
        };
        urgency_normal = {
          background = "#1e1e2e";
          foreground = "#cdd6f4";
          frame_color = "#89b4fa";
          timeout = 10;
        };
        urgency_critical = {
          background = "#1e1e2e";
          foreground = "#cdd6f4";
          frame_color = "#f38ba8";
          timeout = 0;
        };
      };
    };

    programs.kitty = {
      enable = true;
      settings = {
        include = "colors.conf";
        window_padding_width = 10;
        background_opacity = "0.85";
        background_blur = 1;
        confirm_os_window_close = 0;
        font_family = "CaskaydiaCove NF";
        bold_font = "auto";
        italic_font = "auto";
        bold_italic_font = "auto";
        font_size = 11;
        cursor_shape = "beam";
        cursor_beam_thickness = "1.5";
        cursor_blink_interval = "0.5";
        scrollback_lines = 10000;
        enable_audio_bell = false;
      };
      keybindings = {
        "ctrl+equal" = "change_font_size all +1.0";
        "ctrl+minus" = "change_font_size all -1.0";
        "ctrl+0" = "change_font_size all 0";
      };
    };

    wayland.windowManager.hyprland = {
      enable = true;
      extraConfig =
        builtins.readFile ./hyprland.conf
        + (lib.optionalString (vars.shell == "waybar") ''

          # --- Waybar shell ---
          exec-once = waybar

          # Launcher via Rofi (Super tap = open, Super+key = normal shortcut)
          bindr = $mainMod, Super_L, exec, pkill rofi || rofi -show drun
        '');
    };
  };
}
