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

-- Setup lazy.nvim with LazyVim plugins
require("lazy").setup("lazyvim.plugins")

-- Load custom config after LazyVim
require("config").setup()
