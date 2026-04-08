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

-- Wait for plugins to be installed, then load custom config
vim.defer_fn(function()
  -- Load options first
  pcall(require, "config.options")
  pcall(require, "config.keymaps")
  pcall(require, "config.autocmds")

  -- Load plugins
  pcall(require, "plugins.lsp")
  pcall(require, "plugins.ai")
  pcall(require, "plugins.editor")
  pcall(require, "plugins.git")
  pcall(require, "plugins.ui")

  -- Call setup on each if available
  local function try_setup(mod)
    if pcall(require, mod) then
      local ok, m = pcall(require, mod)
      if ok and m and m.setup then
        pcall(m.setup)
      end
    end
  end

  try_setup("plugins.editor")
  try_setup("plugins.git")
  try_setup("plugins.lsp")
  try_setup("plugins.ai")
  try_setup("plugins.ui")
end, 500)
