{
  pkgs,
  vars,
  ...
}:

let
  myScripts = builtins.map (
    name: pkgs.writeShellScriptBin name (builtins.readFile ./scripts/${name}.sh)
  ) [ "update-sys" ];
in
{
  home = {
    packages = myScripts ++ [ pkgs.sshfs ];
    sessionPath = [ "$HOME/.local/bin" ];

    file."wrk/.stignore".text = ''
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
  };

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
      nalyx = "cd ~/nalyx";
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
}
