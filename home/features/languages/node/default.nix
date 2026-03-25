{ config, pkgs, ... }:

{
  home = {
    packages = with pkgs; [
      nodejs_22

      nodePackages.pnpm
      yarn

      typescript-language-server
      vscode-langservers-extracted
      nodePackages.prettier
      nodePackages.typescript

      nodePackages.nodemon
      nodePackages.npm-check-updates
    ];

    sessionVariables = {
      NODE_PATH = "$HOME/.npm-packages/lib/node_modules";
    };

    sessionPath = [
      "$HOME/.npm-packages/bin"
    ];

    file.".npmrc".text = ''
      prefix=''${HOME}/.npm-packages
    '';
  };
}
