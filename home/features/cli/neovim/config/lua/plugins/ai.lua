-- AI Plugins - lazy-loaded, optional
local M = {}

function M.setup()
  -- Copilot
  vim.g.copilot_enabled = true
  vim.g.copilot_filetypes = {
    javascript = true,
    typescript = true,
    python = true,
    go = true,
    rust = true,
    java = true,
    lua = true,
    nix = true,
    markdown = true,
    yaml = true,
    json = true,
    html = true,
    css = true,
  }
  vim.g.copilot_completion_keybindings = {} -- Use Ctrl+Tab for completion
  vim.keymap.set("i", "<C-J>", "copilot#Accept()", { expr = true, silent = true, desc = "Accept Copilot suggestion" })

  -- Avante.nvim - AI chat sidebar
  vim.keymap.set("n", "<leader>aa", "<Cmd>AvanteStart<CR>", { desc = "Toggle Avante chat" })
  vim.keymap.set("v", "<leader>aa", "<Cmd>AvanteVisual<CR>", { desc = "Send selection to Avante" })
end

return M
