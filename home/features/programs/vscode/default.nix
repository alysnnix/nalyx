{
  pkgs,
  osConfig,
  ...
}:
let
  isWSL = osConfig.wsl.enable or false;
in
{
  home.packages = with pkgs; [
    vscode
  ];

  programs.vscode = {
    enable = !isWSL;
  };
}
