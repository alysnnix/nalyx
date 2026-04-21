return {
  -- Disable Mason (LSP servers installed via Nix)
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },

  -- LSP configuration
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ts_ls = {},
        pyright = {},
        gopls = {},
        jdtls = {},
        nil_ls = {},
        texlab = {},
        lua_ls = {
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              completion = { callSnippet = "Replace" },
            },
          },
        },
      },
    },
  },

  -- Disable conform.nvim Mason integration, formatters are on PATH via Nix
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        nix = { "nixfmt" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        typescriptreact = { "prettier" },
        javascriptreact = { "prettier" },
        json = { "prettier" },
        html = { "prettier" },
        css = { "prettier" },
        python = { "black" },
        go = { "gofmt" },
        lua = { "stylua" },
        tex = { "latexindent" },
        latex = { "latexindent" },
      },
    },
  },
}
