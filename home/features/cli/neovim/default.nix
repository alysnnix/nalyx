{ pkgs, ... }:
{
  home.packages = with pkgs; [
    neovim

    # Telescope dependencies
    ripgrep
    fd

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
    texlivePackages.latexindent

    # Build dependency for avante.nvim
    gcc
    gnumake
  ];

  # Deploy Lua config to ~/.config/nvim/
  xdg.configFile = {
    "nvim/init.lua".source = ./config/init.lua;
    "nvim/lua/config/options.lua".source = ./config/lua/config/options.lua;
    "nvim/lua/config/keymaps.lua".source = ./config/lua/config/keymaps.lua;
    "nvim/lua/config/autocmds.lua".source = ./config/lua/config/autocmds.lua;
    "nvim/lua/plugins/ui.lua".source = ./config/lua/plugins/ui.lua;
    "nvim/lua/plugins/editor.lua".source = ./config/lua/plugins/editor.lua;
    "nvim/lua/plugins/lsp.lua".source = ./config/lua/plugins/lsp.lua;
    "nvim/lua/plugins/git.lua".source = ./config/lua/plugins/git.lua;
    "nvim/lua/plugins/ai.lua".source = ./config/lua/plugins/ai.lua;
  };
}
