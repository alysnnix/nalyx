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
    home.packages =
      with pkgs;
      [
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
      ]
      ++ (lib.optionals (vars.shell == "waybar") [
        dunst
      ]);

    # Ensure colors.conf exists before Hyprland starts (Matugen generates it later)
    home.activation.ensureHyprColors = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p ~/.config/hypr
      [ -f ~/.config/hypr/colors.conf ] || touch ~/.config/hypr/colors.conf
    '';

    programs.kitty = {
      enable = true;
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
          exec-once = dunst
        '');
    };
  };
}
