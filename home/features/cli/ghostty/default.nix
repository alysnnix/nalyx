{
  pkgs,
  lib,
  ...
}:
let
  defaultConfig = pkgs.writeText "ghostty-default-config" ''
    font-family = JetBrainsMono Nerd Font
    font-style = bold

    # Follow system color-scheme (GNOME light/dark toggle)
    theme = light:Catppuccin Latte,dark:Catppuccin Mocha

    window-width = 100
    window-height = 27
    window-padding-x = 16
    window-padding-y = 16

    # Close surface immediately so ctrl+w doesn't show a confirmation prompt
    confirm-close-surface = false

    keybind = alt+shift+d=new_split:right
    keybind = ctrl+w=close_surface
    keybind = ctrl+t=new_tab

    # Copy on ctrl+c only when there's a selection (else falls through as SIGINT)
    keybind = performable:ctrl+c=copy_to_clipboard
    keybind = ctrl+v=paste_from_clipboard
  '';
in
{
  home.packages = [ pkgs.ghostty ];

  # Write config as a real file (not symlink) so it stays editable at runtime
  home.activation.ghosttySettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ~/.config/ghostty
    if [ ! -f ~/.config/ghostty/config ] || [ -L ~/.config/ghostty/config ]; then
      rm -f ~/.config/ghostty/config
      install -m 644 ${defaultConfig} ~/.config/ghostty/config
    fi
  '';
}
