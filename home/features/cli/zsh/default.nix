{
  pkgs,
  vars,
  lib,
  hasPrivate ? false,
  private ? null,
  ...
}:

let
  publicScripts = builtins.map (
    name: pkgs.writeShellScriptBin name (builtins.readFile ./scripts/${name}.sh)
  ) [ "update-sys" ];

  privateScripts =
    if hasPrivate then
      builtins.map
        (name: pkgs.writeShellScriptBin name (builtins.readFile "${private}/scripts/${name}.sh"))
        [
          "szn-merge"
          "szn-merge-pr"
          "szn-ssm"
        ]
    else
      [ ];

  myScripts = publicScripts ++ privateScripts;
in
{
  home.packages = myScripts ++ [ pkgs.sshfs ];
  home.sessionPath = [ "$HOME/.local/bin" ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initContent = ''
      # Accept autosuggestions with Ctrl+Space
      bindkey '^ ' autosuggest-accept
    '';

    shellAliases = {
      l = "ls -la";
      switch = "update-sys";
      pull = "git stash && git pull && git stash pop";
      secrets = ''EDITOR="code --wait" nix-shell -p sops --run "sops ~/nalyx/.private/nalyx-private/secrets/secrets.yaml"'';
      nalyx = "cd ~/nalyx";
      szn = "cd ~/wrk/seazone-tech";
      mount-homelab = "mkdir -p ~/mnt/homelab && sshfs ${vars.user.name}@${vars.homelab.address}:/data/sync ~/mnt/homelab -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3";
      umount-homelab = "fusermount -u ~/mnt/homelab";
    };

    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [
        "git"
        "sudo"
        "docker"
      ];
    };
  };

  home.file."wrk/.stignore".text = ''
    node_modules
    .cache
    .next
    target
    dist
    __pycache__
    .venv
    *.tmp
    .direnv
    .devenv
    .terraform
    vendor
  '';
}
