-- Bootstrap lazy.nvim and load LazyVim
-- This file is deployed to ~/.config/nvim/init.lua

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

-- Setup lazy.nvim with all plugins
require("lazy").setup({
  -- LazyVim extras that we use
  { "catppuccin/nvim", lazy = false },
  { "nvim-neo-tree/neo-tree.nvim", lazy = true },
  { "nvim-telescope/telescope.nvim", lazy = true },
  { "lewis6991/gitsigns.nvim", lazy = true },
  { "akinsho/toggleterm.nvim", lazy = true },
  { "github/copilot.vim", lazy = true },
  { "yetone/avante.nvim", lazy = true },

  -- Dependencies
  { "nvim-lua/plenary.nvim", lazy = true },
  { "nvim-tree/nvim-web-devicons", lazy = true },
}, {
  install = { colourscheme = { "catppuccin" } },
  defaults = {
    lazy = false,
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
      },
    },
  },
})

-- Load custom config after plugins
vim.api.nvim_create_autocmd("User", {
  pattern = "LazyInit",
  once = true,
  callback = function()
    require("config").setup()
  end,
})

-- Fallback: if LazyInit doesn't fire, setup after a tick
vim.defer_fn(function()
  if package.loaded["config"] then return end
  pcall(require, "config")
end, 100)
