{ pkgs, ... }:

let
  firefox-launcher = pkgs.makeDesktopItem {
    name = "firefox-profiles";
    desktopName = "Firefox Profiles";
    exec = "firefox --ProfileManager %u";
    icon = "firefox";
    terminal = false;
    categories = [
      "Network"
      "WebBrowser"
    ];
    mimeTypes = [
      "text/html"
      "text/xml"
      "application/xhtml+xml"
    ];
  };
in
{
  programs.firefox.enable = true;
  home.packages = [
    firefox-launcher
  ];

  home.shellAliases = {
    ff = "firefox --ProfileManager";
  };
}
