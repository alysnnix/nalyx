{
  pkgs,
  lib,
  enableClaude ? true,
  enableGemini ? true,
  enableOpencode ? true,
  isServer ? false,
  isInstaller,
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
    ./syncthing
    ./agent-rules
    ./agent-skills
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
      tree
      zip
      unzip
      gnupg
      pinentry-curses
    ]
    # Cloud, media and day-job tooling. Kept off the installer images: none of
    # it partitions a disk, and it is where the weight is. wrangler alone is
    # 1.78GB, openai-whisper drags in torch, and the gcloud SDK is not far
    # behind, which is what pushed the desktop ISO past an 8GB stick.
    ++ lib.optionals (!isInstaller) [
      imagemagick
      awscli2
      (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
      ssm-session-manager-plugin
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
    ++ lib.optionals (!isServer && !isInstaller) [
      paseo-desktop
      # Browser automation CLI for the agents (Claude Code, omp, Codex). Skipped
      # on servers: it drives a real Chrome, and the package pins one in.
      (pkgs.callPackage ../../../packages/agent-browser.nix { })
    ];

  # The `paseo` CLI's `paseo .` launcher only probes a few hardcoded paths for
  # the desktop app; symlink the Nix build where it looks so `paseo .` finds it.
  # Also gated on the installer: home.file pulls paseo-desktop into the closure
  # through getExe, so leaving it would undo removing it from home.packages.
  home.file."Applications/Paseo.AppImage" = lib.mkIf (!isServer && !isInstaller) {
    source = lib.getExe pkgs.paseo-desktop;
  };
}
