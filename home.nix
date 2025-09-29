{ pkgs, ... }:

{
  imports = [
    # -- setup and core --
    ./modules/cli/core.nix
    ./modules/cli/git.nix
    ./modules/cli/zsh.nix
    ./modules/cli/docker.nix

    # -- lang --
    ./modules/lang/go.nix
    ./modules/lang/rust.nix
    ./modules/lang/nodejs.nix
    ./modules/lang/python.nix
  ];

  home.username = "aly";
  home.homeDirectory = "/home/aly";
  home.stateVersion = "24.05";

  programs.home-manager.enable = true;

  home.packages = [
    pkgs.neovim
    pkgs.ripgrep
  ];
}
