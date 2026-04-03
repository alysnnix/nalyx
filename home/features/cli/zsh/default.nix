{
  pkgs,
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
  home.packages = myScripts;
  home.sessionPath = [ "$HOME/.local/bin" ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initContent = ''
      # Tab completes normally AND accepts autosuggestions when present
      ZSH_AUTOSUGGEST_ACCEPT_WIDGETS+=(menu-complete)
      bindkey '^I' menu-complete
    '';

    shellAliases = {
      l = "ls -la";
      switch = "update-sys";
      pull = "git stash && git pull && git stash pop";
      secrets = ''EDITOR="code --wait" nix-shell -p sops --run "sops ~/nalyx/.private/nalyx-private/secrets/secrets.yaml"'';
      nalyx = "cd ~/nalyx";
      szn = "cd ~/wrk/seazone-tech";
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
