-- UI plugins: catppuccin, bufferline, lualine
local M = {}

function M.setup()
  -- Catppuccin theme
  local catppuccin = require("catppuccin")
  catppuccin.setup({
    flavour = "mocha",
    transparent_background = false,
    show_end_of_buffer = false,
    term_colors = false,
    dim_inactive = {
      enabled = false,
      shade = "dark",
      percentage = 0.15,
    },
    styles = {
      comments = { "italic" },
      conditionals = { "italic" },
      loops = {},
      functions = {},
      keywords = {},
      strings = {},
      variables = {},
      numbers = {},
      booleans = {},
      properties = {},
      types = {},
      operators = {},
    },
    color_overrides = {},
    custom_highlights = {},
    integrations = {
      aerial = false,
      alert = false,
      Neogit = true,
      minibuffer = true,
      telescope = {
        enabled = true,
        highlights = {
          TelescopeMatching = { fg = "#cba6f7" },
        },
      },
      which = false,
    },
  })

  -- Apply theme
  vim.cmd.colorscheme("catppuccin")

  -- Transparent floating windows
  vim.api.nvim_create_autocmd("User", {
    pattern = "TerarlFloatWintheme",
    callback = function()
      vim.cmd("highlight FloatBorder guibg=NormalFloat guifg=Overlay")
    end,
  })

  -- Lualine
  local lualine = require("lualine")
  lualine.setup({
    options = {
      theme = "catppuccin",
      section_separators = "",
      component_separators = "",
      globalstatus = true,
      disabled_filetypes = {
        statusline = {},
        winbar = {},
      },
    },
    sections = {
      lualine_a = { "mode" },
      lualine_b = { "branch" },
      lualine_c = {
        {
          "diagnostics",
          symbols = {
            error = " ",
            warn = " ",
            info = " ",
            hint = "💡 ",
          },
        },
        { "filetype", icon = "󰈭" },
      },
      lualine_x = {
        {
          "diff",
          symbols = {
            added = " ",
            modified = " ",
            removed = " ",
          },
        },
        "encoding",
        "fileformat",
      },
      lualine_y = { "progress" },
      lualine_z = { "location" },
    },
    extensions = { "neo-tree", "toggleterm" },
  })

  -- Bufferline (tabs)
  local bufferline = require("bufferline")
  vim.keymap.set("n", "<C-Tab>", "<Cmd>BufferLineCycleNext<CR>", { desc = "Next buffer" })
  vim.keymap.set("n", "<C-S-Tab>", "<Cmd>BufferLineCyclePrev<CR>", { desc = "Previous buffer" })
end

return M
