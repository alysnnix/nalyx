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
  ++ (lib.optional (vars.desktop == "gnome") ./features/desktop/gnome)
  ++ (lib.optional (vars.desktop == "hyprland") ./features/desktop/hyprland)
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
      EDITOR = "vim";
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

  qt = lib.mkIf (vars.desktop != null) {
    enable = true;
    platformTheme.name = "adwaita";
    style = {
      name = "adwaita-dark";
      package = pkgs.adwaita-qt;
    };
  };

  programs.home-manager.enable = true;
}
