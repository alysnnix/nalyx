{
  config,
  lib,
  pkgs,
  vars,
  ...
}:

{
  imports = [
    ./caelestia
    ./matugen
  ];

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
      light
      playerctl
      kitty
      nautilus
      thunderbird
      qalculate-gtk
      nwg-look
    ];

    wayland.windowManager.hyprland = {
      enable = true;
      extraConfig = builtins.readFile ./hyprland.conf;
    };
  };
}
