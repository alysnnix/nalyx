{
  config,
  lib,
  pkgs,
  vars,
  ...
}:

{
  imports = [
    ./waybar
    ./rofi
  ];

  options.modules.desktop.hyprland = {
    enable = lib.mkEnableOption "Habilita o ambiente Hyprland";
  };

  config = lib.mkIf (vars.desktop == "hyprland") {
    home.packages = with pkgs; [
      rofi
      swww
      dunst
      wl-clipboard
      grim
      slurp
      pamixer
      light
      playerctl
      kitty
      nautilus
    ];

    xdg.configFile."hypr/colors".text = ''
      $background = rgba(1d192bee)
      $foreground = rgba(c3dde7ee)
      # ... suas cores ...
    '';

    wayland.windowManager.hyprland = {
      enable = true;
      extraConfig = builtins.readFile ./hyprland.conf;
    };
  };
}
