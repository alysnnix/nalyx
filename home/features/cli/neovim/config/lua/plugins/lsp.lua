-- LSP Configuration - Mason disabled, using system LSP servers from Nix
local M = {}

function M.setup()
  -- Configure LSP servers installed via Nix
  -- These are automatically detected by nvim-lspconfig
  require("lspconfig").lua_ls.setup({
    settings = {
      Lua = {
        runtime = { version = "LuaJIT" },
        diagnostics = { globals = { "vim" } },
        workspace = {
          library = vim.api.nvim_get_runtime_file("", true),
          checkThirdParty = false,
        },
        telemetry = { enable = false },
      },
    },
  })

  require("lspconfig").nil_ls.setup({
    settings = {
      ["nil"] = {
        formatting = {
          command = { "nixfmt" },
        },
      },
    },
  })

  require("lspconfig").pyright.setup({
    settings = {
      python = {
        analysis = {
          autoSearchPaths = true,
          useLibraryCodeForTypes = true,
          typeCheckingMode = "basic",
        },
      },
    },
  })

  require("lspconfig").ts_ls.setup({
    on_attach = function(client, bufnr)
      -- Disable formatting for ts_ls (let prettier handle it)
      client.server_capabilities.documentFormattingProvider = false
    end,
  })

  require("lspconfig").gopls.setup({
    settings = {
      gopls = {
        analyses = {
          unusedparams = true,
        },
        staticcheck = true,
      },
    },
  })

  require("lspconfig").jdtls.setup({})

  require("lspconfig").texlab.setup({})

  -- Global LSP keybindings
  vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Hover documentation" })
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
  vim.keymap.set("n", "gr", vim.lsp.buf.references, { desc = "Find references" })
  vim.keymap.set("n", "gi", vim.lsp.buf.implementation, { desc = "Find implementations" })
  vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, { desc = "Signature help" })
  vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename symbol" })
  vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code actions" })
  vim.keymap.set("n", "[d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
  vim.keymap.set("n", "]d", vim.diagnostic.goto_prev, { desc = "Previous diagnostic" })
  vim.keymap.set("n", "<leader>dl", vim.diagnostic.setloclist, { desc = "Diagnostics list" })

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

  -- LSP status in lualine (handled by lazyvim)
end

return M
