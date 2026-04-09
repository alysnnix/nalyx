return {
  -- Catppuccin color scheme
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      integrations = {
        cmp = true,
        gitsigns = true,
        neo_tree = true,
        telescope = { enabled = true },
        treesitter = true,
        native_lsp = {
          enabled = true,
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
          },
        },
      },
    },
  },

  -- Set catppuccin as the colorscheme
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },

  -- Use Nerd Font glyph icons
  {
    "nvim-mini/mini.icons",
    opts = {
      style = "glyph",
    },
  },

  -- Bufferline customization (already included by LazyVim)
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        always_show_bufferline = true,
        separator_style = "thin",
        middle_mouse_command = "bdelete! %d",
      },
    },
  },

  -- Lualine customization (already included by LazyVim)
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      options = {
        theme = "catppuccin",
      },
    },
  },

  -- Minimap
  {
    "nvim-mini/mini.map",
    event = "VeryLazy",
    opts = {
      integrations = nil,
      window = {
        width = 10,
        winblend = 50,
        show_integration_count = false,
      },
    },
    config = function(_, opts)
      local map = require("mini.map")
      opts.integrations = {
        map.gen_integration.builtin_search(),
        map.gen_integration.gitsigns(),
        map.gen_integration.diagnostic(),
      }
      map.setup(opts)
      map.open()
    end,
  },
}
