{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [ ./config ];

  home.packages = with pkgs; [
    # Neovim
    neovim

    # LSP servers
    nodePackages.typescript-language-server
    pyright
    gopls
    jdt-language-server
    nil
    texlab
    lua-language-server

    # Formatters
    nixfmt
    nodePackages.prettier
    black
    stylua
    latexindent

    # Telescope dependencies
    ripgrep
    fd
  ];

  # Deploy LazyVim config files to ~/.config/nvim/
  home.file."${config.home.homeDirectory}/.config/nvim/init.lua".source = ./config/init.lua;
  home.file."${config.home.homeDirectory}/.config/nvim/lazyvim.json".source = ./config/lazyvim.json;
  home.file."${config.home.homeDirectory}/.config/nvim/lua".source = ./config/lua;
}
