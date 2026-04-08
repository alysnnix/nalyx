{
  config,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    neovim
    ripgrep
    fd
    nodePackages.typescript-language-server
    pyright
    gopls
    nil
    lua-language-server
    nixfmt
    nodePackages.prettier
    black
    stylua
  ];

  # Deploy LazyVim config
  home.file."${config.home.homeDirectory}/.config/nvim/init.lua".text = ''
    -- Bootstrap lazy.nvim
    local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"
    if not (vim.uv or vim.loop).fs_stat(lazypath) then
      vim.fn.system {
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--depth=1",
        lazypath,
      }
    end
    vim.opt.rtp:prepend(lazypath)

    -- Load LazyVim
    require("lazy").setup("lazyvim.plugins")
  '';

  home.file."${config.home.homeDirectory}/.config/nvim/lazyvim.json".text = ''
    {
      "extras": true
    }
  '';
}
