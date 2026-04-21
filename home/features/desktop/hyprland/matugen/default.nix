{ pkgs, ... }:
{
  home.packages = with pkgs; [
    matugen
    swww
  ];

  xdg.configFile."matugen/templates" = {
    source = ./templates;
    recursive = true;
  };

  xdg.configFile."matugen/config.toml".text = ''
    [config]
    reload_on_change = true

    # Hyprland border colors
    [templates.hyprland]
    input_path = "~/.config/matugen/templates/hyprland-colors.conf"
    output_path = "~/.config/hypr/colors.conf"
    post_hook = "hyprctl reload"

    # Kitty terminal colors
    [templates.kitty]
    input_path = "~/.config/matugen/templates/kitty-colors.conf"
    output_path = "~/.config/kitty/colors.conf"
    post_hook = "pkill -SIGUSR1 kitty || true"
  '';
}
