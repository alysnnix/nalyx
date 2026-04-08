-- Editor plugins: neo-tree, telescope, toggleterm
local M = {}

function M.setup()
  -- Neo-tree (lazy-loaded by LazyVim, but we configure here)
  vim.keymap.set("n", "<C-e>", "<Cmd>Neotree toggle<CR>", { desc = "Toggle file tree" })
  vim.keymap.set("n", "<leader>e", "<Cmd>Neotree reveal<CR>", { desc = "Reveal current file" })

  -- Telescope
  local telescope = require("telescope")
  telescope.setup({
    defaults = {
      layout_strategy = "horizontal",
      layout_config = {
        width = 0.85,
        height = 0.85,
        preview_width = 0.5,
      },
      file_ignore_patterns = {
        "node_modules",
        ".git",
        "__pycache__",
        "%.o",
        "target",
        "dist",
        ".next",
        ".cache",
      },
      mappings = {
        i = {
          ["<C-j>"] = require("telescope.actions").move_selection_next,
          ["<C-k>"] = require("telescope.actions").move_selection_previous,
          ["<C-q>"] = require("telescope.actions").send_to_qflist,
          ["<C-l>"] = require("telescope.actions").completeing,
        },
      },
    },
    pickers = {
      find_files = {
        theme = "dropdown",
        previewer = false,
      },
      live_grep = {
        theme = "ivy",
      },
    },
    extensions = {
      fzf = {
        fuzzy = true,
        override_generic_sorter = true,
        override_file_sorter = true,
      },
    },
  })

  -- Load extensions
  pcall(require("telescope").load_extension, "fzf")

  -- File previewer for telescope
  require("telescope").setup({
    defaults = {
      file_sorter = require("telescope.sorters").get_fuzzy_file,
    },
  })

  -- ToggleTerm
  local toggleterm = require("toggleterm")
  toggleterm.setup({
    size = function(term)
      if term.direction == "horizontal" then
        return 15
      elseif term.direction == "vertical" then
        return vim.o.columns * 0.4
      end
    end,
    open_mapping = [[<A-q>]],
    direction = "horizontal",
    shell = vim.o.shell,
    -- Float config for floating terminal
    float_opts = {
      border = "curved",
      winblend = 10,
    },
  })

  -- Lazygit toggle (integrated terminal)
  vim.keymap.set("n", "<C-g>", "<Cmd>LazyGit<CR>", { desc = "Open lazygit" })

  -- Quickfix toggle
  vim.keymap.set("n", "<leader>q", "<Cmd>copen<CR>", { desc = "Open quickfix" })
end

return M
