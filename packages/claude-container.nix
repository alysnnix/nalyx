# Minimal Docker image for running Claude Code with full permissions.
# Build:  nix build .#claude-container
# Load:   docker load < result   (or use the cc() shell function)
{ pkgs, ... }:

let
  devTools = with pkgs; [
    # Shell
    bash
    zsh

    # Core Unix
    coreutils
    findutils
    gnused
    gnugrep
    gawk
    which
    less
    procps
    diffutils

    # Network / VCS
    curl
    wget
    git
    openssh

    # Dev tools
    neovim
    ripgrep
    fd
    jq
    tree
    gnumake
    unzip
    zip
    gh

    # Runtimes (MCP servers via npx, project builds)
    nodejs_22
    python3

    # SSL
    cacert
  ];

  # Merge all binaries under a single /bin so PATH stays simple
  env = pkgs.buildEnv {
    name = "claude-container-env";
    paths = [ pkgs.claude-code ] ++ devTools;
    pathsToLink = [
      "/bin"
      "/lib"
      "/lib64"
      "/etc"
      "/share"
    ];
    ignoreCollisions = true;
  };
in
pkgs.dockerTools.buildLayeredImage {
  name = "claude-code-container";
  tag = "latest";

  contents = [
    env
    pkgs.dockerTools.caCertificates # /etc/ssl/certs
    pkgs.dockerTools.fakeNss # minimal /etc/passwd, /etc/group, nsswitch.conf
  ];

  # Runs as fakeroot — sets up the filesystem layout inside the image
  fakeRootCommands = ''
    mkdir -p /tmp /workspace /home/claude /usr/bin /bin /run
    chmod 1777 /tmp
    chmod 755  /home/claude

    # fakeNss only ships root + nobody; add the claude user
    echo "claude:x:1000:1000:Claude Code:/home/claude:/bin/bash" >> /etc/passwd
    echo "claude:x:1000:"                                          >> /etc/group
    echo "claude:!:19700:0:99999:7:::"                            >> /etc/shadow
    chown 1000:1000 /home/claude

    # Standard symlinks expected by many scripts
    ln -sf ${env}/bin/bash /bin/bash
    ln -sf ${env}/bin/bash /bin/sh
    ln -sf ${env}/bin/env  /usr/bin/env
  '';

  enableFakechroot = true;

  config = {
    # CMD is appended to ENTRYPOINT; leave empty so cc() can pass extra args cleanly
    Entrypoint = [
      "claude"
      "--dangerously-skip-permissions"
    ];
    Cmd = [ ];

    User = "1000";

    Env = [
      "PATH=${env}/bin"
      "HOME=/home/claude"
      "USER=claude"
      "TERM=xterm-256color"
      # SSL for curl, git, node, python
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "NODE_EXTRA_CA_CERTS=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ];

    WorkingDir = "/workspace";
    Volumes = {
      "/workspace" = { };
    };
  };
}
