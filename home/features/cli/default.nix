{
  pkgs,
  lib,
  enableClaude ? true,
  enableGemini ? true,
  enableOpencode ? true,
  isServer ? false,
  ...
}:
{
  imports = [
    ./zsh
    ./git
    ./ssh
    ./neovim
    ./ghostty
    ./herdr
    ./omp
  ]
  ++ (lib.optional enableGemini ./gemini)
  ++ (lib.optional enableClaude ./claude)
  ++ (lib.optional enableOpencode ./opencode);

  home.packages =
    with pkgs;
    [
      glow
      omp
      herdr
      paseo
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
      (pkgs.callPackage ../../../packages/composio-cli.nix { })
      ffmpeg
      openai-whisper
    ]
    ++ lib.optionals (!isServer) [
      paseo-desktop
    ];

  # The `paseo` CLI's `paseo .` launcher only probes a few hardcoded paths for
  # the desktop app; symlink the Nix build where it looks so `paseo .` finds it.
  home.file."Applications/Paseo.AppImage" = lib.mkIf (!isServer) {
    source = lib.getExe pkgs.paseo-desktop;
  };
}
