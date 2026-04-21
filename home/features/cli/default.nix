{
  pkgs,
  lib,
  enableClaude ? true,
  enableGemini ? true,
  enableOpencode ? true,
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
  ++ (lib.optional enableOpencode ./opencode);

  home.packages = with pkgs; [
    ghostty
    glow
    lazygit
    imagemagick
    tree
    awscli2
    ssm-session-manager-plugin
    zip
    unzip
    gnupg
    pinentry-curses
    stripe-cli
    supabase-cli
    flyctl
    kubectl
    (pkgs.callPackage ../../../packages/render-cli.nix { })
  ];
}
