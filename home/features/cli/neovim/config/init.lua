-- Bootstrap lazy.nvim and setup plugins
-- This file is deployed to ~/.config/nvim/init.lua

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

-- Load plugins and config
require("lazy").setup({
  { "catppuccin/nvim", lazy = false },
  { "nvim-neo-tree/neo-tree.nvim", branch = "v3.x", dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons" } },
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
  { "lewis6991/gitsigns.nvim" },
  { "akinsho/toggleterm.nvim" },
  { "github/copilot.vim" },
  { "yetone/avante.nvim" },
  { "nvim-lua/plenary.nvim" },
  { "nvim-tree/nvim-web-devicons" },
  { "folke/lazy.nvim" },
  { "nvim-lualine/lualine.nvim" },
})

-- Load config after plugins
require("config")
