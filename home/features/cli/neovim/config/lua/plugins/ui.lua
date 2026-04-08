-- UI plugins: catppuccin, bufferline, lualine
local M = {}

function M.setup()
  -- Catppuccin theme
  local catppuccin = require("catppuccin")
  catppuccin.setup({
    flavour = "mocha",
  })
  vim.cmd.colorscheme("catppuccin")

  -- Lualine
  local ok, lualine = pcall(require, "lualine")
  if ok then
    lualine.setup({
      options = {
        theme = "catppuccin",
        globalstatus = true,
      },
    })
  end

  -- Bufferline tabs
  vim.keymap.set("n", "<C-Tab>", "<Cmd>BufferLineCycleNext<CR>", { desc = "Next buffer" })
  vim.keymap.set("n", "<C-S-Tab>", "<Cmd>BufferLineCyclePrev<CR>", { desc = "Previous buffer" })
end

return M
