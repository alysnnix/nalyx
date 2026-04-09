{
  pkgs,
  lib,
  enableClaude ? true,
  enableGemini ? true,
  hasPrivate ? false,
  private ? null,
  ...
}:
{
  imports = [
    ./zsh
    ./git
    ./ssh
    ./neovim
  ]
  ++ (lib.optional enableGemini ./gemini)
  ++ (lib.optional enableClaude ./claude)
  ++ (lib.optional hasPrivate "${private}/home/features/cli/wrk.nix");

  home.packages = with pkgs; [
    ghostty
    lazygit
    imagemagick
    tree
    awscli2
    ssm-session-manager-plugin
    zip
    unzip
    gnupg
    pinentry-curses
    supabase-cli
    flyctl
    (pkgs.callPackage ../../../packages/render-cli.nix { })
  ];
}
