{ pkgs, ... }:

{
  home.packages = with pkgs; [
    git
    gh
  ];

  programs.git = {
    enable = true;
    userName = "aly";
    userEmail = "4ly.alcantara@gmail.com";

    extraConfig = {
      init.defaultBranch = "main";
      core.editor = "nano";
      pull.rebase = false;
      github.user = "alysnnix";
    };

    ignores = [
      ".DS_Store"
      "*.swp"
      "*.swo"
      ".envrc"
      ".direnv/"
      "__pycache__/"
    ];
  };

  programs.gh = {
    enable = true;
  };
}
