{ pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    nerd-fonts.hack
    mpc
  ];

  programs.waybar = {
    enable = true;
    package = pkgs.waybar;
  };

  xdg.configFile."waybar/config.jsonc".source = ./config.jsonc;
  xdg.configFile."waybar/style.css".source = ./style.css;
}
