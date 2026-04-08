-- LSP Configuration
-- Note: LSP will auto-enable when filetypes are detected
-- Server configuration can be added later via vim.lsp.config
local M = {}

function M.setup()
  -- Enable the built-in LSP
  vim.lsp.enable(true)

  -- Global LSP keybindings
  vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover documentation" })
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
  vim.keymap.set("n", "gr", vim.lsp.buf.references, { desc = "Find references" })
  vim.keymap.set("n", "gi", vim.lsp.buf.implementation, { desc = "Find implementations" })
  vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, { desc = "Signature help" })
  vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename symbol" })
  vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code actions" })

  -- Enable diagnostics
  vim.diagnostic.config({
    virtual_text = {
      prefix = "●",
      source = "if_many",
    },
    signs = true,
    underline = true,
    update_in_insert = false,
    severity_sort = true,
  })
end

return M
