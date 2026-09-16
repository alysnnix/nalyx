{
  pkgs,
  lib,
  enableClaude ? true,
  enableGemini ? true,
  enableOpencode ? true,
  enablePi ? true,
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
    ./syncthing
    # Imported unconditionally like ./syncthing: it declares an option and
    # gates its own config on it, so a host that does not want it pays nothing
    # and no `imports` position ever reads a specialArg.
    ./orca
    # Same shape: a static path in `imports`, and the module itself reads the
    # host-shape specialArgs from `config` positions only.
    ./paseo
    # Option surface for the per-project private layer. Imported here because
    # this is the one module every profile pulls in, including NixOS hosts.
    ./wrk.nix
    ./agent-rules
    ./agent-skills
  ]
  ++ (lib.optional enableGemini ./gemini)
  ++ (lib.optional enableClaude ./claude)
  ++ (lib.optional enableOpencode ./opencode)
  ++ (lib.optional enablePi ./pi);

  home.packages =
    with pkgs;
    [
      glow
      omp
      herdr
      # Codex CLI straight from nixpkgs, not from the llm-agents overlay: that
      # flake exposes only claude-code, omp and pi here, and nixpkgs already
      # carries codex with hydra-built substitutes. No module of its own, so
      # `~/.codex/AGENTS.md` keeps landing through the `command -v codex` probe
      # in ./agent-rules.
      codex
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
      bitwarden-cli
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
    ];
}
