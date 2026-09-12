{
  pkgs,
  lib,
  enableClaude ? true,
  enableGemini ? true,
  enableOpencode ? true,
  enablePi ? true,
  # Mirrors `hasDesktop` in home/default.nix. WSL is a terminal host whose
  # graphical layer belongs to Windows, so anything that ships a window is as
  # out of place here as it is on a server. Same `config`-position-only rule as
  # `terminalOnly` below.
  isWsl ? false,
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
let
  # The same guard home/default.nix uses for the graphical tree, plus the
  # terminal-only work laptop, which that file never has to consider.
  hasDesktop = !isWsl && !isServer && !terminalOnly;
in
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
    # An Electron app with a window, so it follows the same rule as the rest of
    # the graphical tree. The daemon is the half that matters and it is a plain
    # service: on WSL it is declared in hosts/wsl and the client lives on the
    # Windows side, either the bundled web UI in a browser or the Windows build
    # of this same app tunnelling in over SSH.
    ++ lib.optionals hasDesktop [
      paseo-desktop
    ];

  # The `paseo` CLI's `paseo .` launcher only probes a few hardcoded paths for
  # the desktop app; symlink the Nix build where it looks so `paseo .` finds it.
  # The `.AppImage` name is what the launcher probes for, not a description of
  # the target: nix/desktop-package.nix produces a shell wrapper around
  # electron, never an AppImage.
  home.file."Applications/Paseo.AppImage" = lib.mkIf hasDesktop {
    source = lib.getExe pkgs.paseo-desktop;
  };
}
