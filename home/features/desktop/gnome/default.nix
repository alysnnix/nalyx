{
  lib,
  pkgs,
  vars,
  ...
}:

{
  options.modules.desktop.gnome = {
    enable = lib.mkEnableOption "Enable Gnome desktop";
  };

  config = lib.mkIf (vars.desktop == "gnome") {
    dconf.settings = {
      "org/gnome/desktop/input-sources" = {
        sources = [
          (lib.hm.gvariant.mkTuple [
            "xkb"
            "us"
          ])
          (lib.hm.gvariant.mkTuple [
            "xkb"
            "br"
          ])
        ];
        xkb-options = [ "terminate:ctrl_alt_bksp" ];
      };

      "org/gnome/desktop/wm/keybindings" = {
        close = [ "<Control>q" ];
        minimize = [ "<Super>d" ];
      };

      "org/gnome/settings-daemon/plugins/media-keys" = {
        home = [ "<Super>e" ];
        calculator = [ "<Super>c" ];
      };

      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
        binding = "<Super>e";
        command = "nautilus";
        name = "Open Files";
      };

      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = [
          "appindicatorsupport@rgcjonas.gmail.com"
          "just-perfection-desktop@just-perfection"
          "rounded-window-corners@fxgn"
          "Vitals@CoreCoding.com"
          "dash-to-dock@micxgx.gmail.com"
          "unite@hardpixel.eu"
          "gsconnect@andyholmes.github.io" # Adicionado aqui
        ];
      };

      "org/gnome/shell/extensions/unite" = {
        hide-titlebar-when-maximized = true;
        buttons-on-app-menu = true;
        show-app-icon = true;
        hide-window-buttons-on-csd = true;
        buttons-placement = "right";
      };

      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = "adw-gtk3-dark";
      };
    };

    home.packages = with pkgs; [
      gnome-tweaks
      gnomeExtensions.unite
      xprop
      x11perf
      xwininfo
      geary
      gnomeExtensions.gsconnect # Adicionado o pacote da extensão
    ];
  };
}
