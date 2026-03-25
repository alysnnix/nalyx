{
  pkgs,
  lib,
  enableClaude ? true,
  enableGemini ? true,
  ...
}:
{
  imports = [
    ./zsh
    ./git
    ./ssh
  ]
  ++ (lib.optional enableGemini ./gemini)
  ++ (lib.optional enableClaude ./claude);

  home.packages = with pkgs; [
    imagemagick
    tree
    awscli2
    zip
    gnupg
    pinentry-curses
    supabase-cli
  ];
}
