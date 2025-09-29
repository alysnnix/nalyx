{ pkgs, ... }:

{
  home.packages = with pkgs; [
    nodejs
  ];

  programs.corepack.enable = true;
}
