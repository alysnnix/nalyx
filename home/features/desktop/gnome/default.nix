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

    # Drop matugen leftovers from a previous Hyprland session that would
    # override the GNOME 49 libadwaita accent-color tokens. Runs before HM
    # link checks so the gtk-4.0 symlink lands without creating a backup.
    home.activation.cleanStaleMatugenGtk = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      for f in "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"; do
        if [ -f "$f" ] && [ ! -L "$f" ] && grep -q "Generated with Matugen" "$f" 2>/dev/null; then
          rm -f "$f"
        fi
      done
    '';

    # Empty gtk-4.0 user css so libadwaita 1.7+ on GNOME 49 keeps its dynamic
    # accent-color tokens. The HM gtk module otherwise imports adw-gtk3-dark
    # here, hardcoding accents and breaking the Settings color swatches.
    xdg.configFile."gtk-4.0/gtk.css".text = lib.mkForce "";
  };
}
