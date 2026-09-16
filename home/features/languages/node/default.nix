{ config, pkgs, ... }:

{
  home = {
    packages = with pkgs; [
      nodejs_22

      pnpm
      yarn

      typescript-language-server
      vscode-langservers-extracted
      prettier
      typescript

      nodemon
      npm-check-updates
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
