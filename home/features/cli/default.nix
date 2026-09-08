{
  pkgs,
  lib,
  enableClaude ? true,
  enableGemini ? true,
  enableOpencode ? true,
  isServer ? false,
  # Terminal-only host: keep the shell, the agents and the CLI toolchain, drop
  # everything that ships a window. Distinct from `isServer`, which describes a
  # headless machine that still syncs with the personal fleet; this describes a
  # managed work laptop where the graphical layer belongs to someone else.
  #
  # Read only from `config` positions below, never from `imports`. A specialArg
  # with a default that is consulted while building the module tree sends the
  # module system to `_module.args`, which needs `config`, and that recurses.
  # Conditional imports are gated by real options instead (see ./syncthing).
  terminalOnly ? false,
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
      # Browser automation CLI for the agents (Claude Code, omp, Codex). Skipped
      # on servers: it drives a real Chrome, and the package pins one in.
      #
      # Kept on terminal-only hosts on purpose: it has no window of its own, and
      # the gb-slack and gb-calendar skills are built on top of it.
      (pkgs.callPackage ../../../packages/agent-browser.nix { })
    ]
    # An AppImage with a GUI, so it goes with the other applications.
    ++ lib.optionals (!isServer && !terminalOnly) [
      paseo-desktop
    ];

  # The `paseo` CLI's `paseo .` launcher only probes a few hardcoded paths for
  # the desktop app; symlink the Nix build where it looks so `paseo .` finds it.
  home.file."Applications/Paseo.AppImage" = lib.mkIf (!isServer && !terminalOnly) {
    source = lib.getExe pkgs.paseo-desktop;
  };
}
