{
  pkgs,
  vars,
  lib,
  isWsl,
  isServer ? false,
  ...
}:
let
  hasDesktop = !isWsl && !isServer;
in
{
  imports = [
    ./features/cli
    ./features/languages
  ]
  ++ (lib.optional (hasDesktop && vars.desktop == "gnome") ./features/desktop/gnome)
  ++ (lib.optional (hasDesktop && vars.desktop == "hyprland") ./features/desktop/hyprland)
  ++ lib.optionals hasDesktop [
    ./features/programs
  ];

  home = {
    username = vars.user.name;
    homeDirectory = "/home/${vars.user.name}";

    packages =
      with pkgs;
      [
        gh
        gnumake
        nerd-fonts.jetbrains-mono
        obsidian
      ]
      ++ lib.optionals hasDesktop [
        spotify
        slack
        (google-chrome.override {
          commandLineArgs = [
            "--ozone-platform-hint=auto"
            "--enable-features=WaylandWindowDecorations"
            "--ignore-gpu-blocklist"
            "--enable-gpu-rasterization"
          ];
        })
      ];

    sessionVariables = {
      EDITOR = "nvim";
      BROWSER = if isWsl then "wslview" else "firefox";
    };

    stateVersion = "25.11";
  };

  gtk = lib.mkIf (vars.desktop != null) {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
  };

  # Force overwrite GTK files that Matugen/Caelestia may have modified
  xdg.configFile."gtk-4.0/gtk.css".force = true;
  xdg.configFile."gtk-4.0/settings.ini".force = true;

  qt = lib.mkIf (vars.desktop != null) {
    enable = true;
    platformTheme.name = "adwaita";
    style = {
      name = "adwaita-dark";
      package = pkgs.adwaita-qt;
    };
  };

  xdg.mimeApps = lib.mkIf isWsl {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "wslview.desktop";
      "x-scheme-handler/https" = "wslview.desktop";
      "x-scheme-handler/file" = "wslview.desktop";
    };
  };

  programs.home-manager.enable = true;
}
