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

    # SSL certs
    cacert
  ];

  env = pkgs.buildEnv {
    name = "claude-container-env";
    paths = [ pkgs.claude-code ] ++ devTools;
    pathsToLink = [
      "/bin"
      "/lib"
      "/lib64"
      "/share"
    ];
    ignoreCollisions = true;
  };
in
pkgs.dockerTools.buildLayeredImage {
  name = "claude-code-container";
  tag = "latest";

  contents = [ env ];

  # fakeRootCommands runs with CWD=$out (the customization layer directory).
  # Without enableFakechroot there is no chroot, so all paths must be RELATIVE
  # (no leading /) — they are resolved relative to $out and become absolute
  # paths inside the final image.
  fakeRootCommands = ''
    mkdir -p tmp workspace home/claude usr/bin bin etc run

    # NSS files required by git, node, ssh, and most Unix programs
    printf '%s\n' \
      'root:x:0:0:root:/root:/bin/sh' \
      'nobody:x:65534:65534:nobody:/nonexistent:/bin/false' \
      'claude:x:1000:1000:Claude Code:/home/claude:/bin/bash' \
      > etc/passwd

    printf '%s\n' \
      'root:x:0:' \
      'nobody:x:65534:' \
      'claude:x:1000:' \
      > etc/group

    printf '%s\n' \
      'passwd:    files' \
      'group:     files' \
      'shadow:    files' \
      'hosts:     files dns' \
      > etc/nsswitch.conf

    echo '127.0.0.1 localhost' > etc/hosts

    chmod 1777 tmp
    chmod 755  home/claude
    chown 1000:1000 home/claude

    # /bin/sh and /usr/bin/env are not provided by buildEnv; create them here
    ln -sf ${env}/bin/bash bin/sh
    ln -sf ${env}/bin/env  usr/bin/env
  '';

  config = {
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
