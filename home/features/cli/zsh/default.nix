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

    shellAliases = {
      l = "ls -la";
      up = "update-sys";
      pull = "git stash && git pull && git stash pop";
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
