{ pkgs, ... }:
{
  home.packages = with pkgs; [
    matugen
    swww
  ];

  # 1. Copia a pasta de templates que você baixou do Dusky
  xdg.configFile."matugen/templates" = {
    source = ./templates;
    recursive = true;
  };

  # 2. Gera o config.toml adaptado
  xdg.configFile."matugen/config.toml".text = ''
    [config]
    reload_on_change = true

    # --- HYPRLAND ---
    [templates.hyprland]
    input_path = "~/.config/matugen/templates/hyprland-colors.conf"
    output_path = "~/.config/hypr/colors.conf"
    post_hook = "hyprctl reload"

    # --- ROFI ---
    [templates.rofi]
    input_path = "~/.config/matugen/templates/rofi-colors.rasi"
    output_path = "~/.config/rofi/colors.rasi"
    # O Rofi recarrega sozinho na próxima vez que abrir

    # --- WAYBAR ---
    [templates.waybar]
    input_path = "~/.config/matugen/templates/colors.css"
    output_path = "~/.config/waybar/colors.css"
    # Recarrega a Waybar suavemente
    post_hook = "pkill -SIGUSR2 waybar || true"

    # --- KITTY (Descomente se você usar o Kitty) ---
    # [templates.kitty]
    # input_path = "~/.config/matugen/templates/kitty-colors.conf"
    # output_path = "~/.config/kitty/colors.conf"
    # post_hook = "pkill -SIGUSR1 kitty || true"

    # --- CAVA (Visualizer de Audio) ---
    # [templates.cava]
    # input_path = "~/.config/matugen/templates/cava-colors.ini"
    # output_path = "~/.config/cava/themes/cava-colors.ini"
    # post_hook = "pkill -USR1 cava || true"
  '';
}
