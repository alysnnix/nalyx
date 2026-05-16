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
    ./ghostty
  ]
  ++ (lib.optional enableGemini ./gemini)
  ++ (lib.optional enableClaude ./claude)
  ++ (lib.optional enableOpencode ./opencode);

  home.packages = with pkgs; [
    glow
    lazygit
    imagemagick
    tree
    awscli2
    (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
    ssm-session-manager-plugin
    zip
    unzip
    gnupg
    pinentry-curses
    stripe-cli
    supabase-cli
    flyctl
    kubectl
    (lib.lowPrio wrangler)
    (pkgs.callPackage ../../../packages/render-cli.nix { })
  ];
}
