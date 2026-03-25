{ pkgs, config, ... }:
{
  home.packages = with pkgs; [
    rofi
    papirus-icon-theme
  ];

  programs.rofi = {
    enable = true;
    package = pkgs.rofi;

    theme = ./style.rasi;
  };

  xdg.configFile."rofi/colors.rasi".source = ./colors.rasi;
}
