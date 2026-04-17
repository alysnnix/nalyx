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
      brightnessctl
      playerctl
      kitty
      nautilus
      thunderbird
      qalculate-gtk
      nwg-look
      btop
    ];

    # Ensure colors.conf exists before Hyprland starts (Matugen generates it later)
    home.activation.ensureHyprColors = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p ~/.config/hypr
      [ -f ~/.config/hypr/colors.conf ] || touch ~/.config/hypr/colors.conf
    '';

    wayland.windowManager.hyprland = {
      enable = true;
      extraConfig = builtins.readFile ./hyprland.conf;
    };
  };
}
