return {
  -- Neo-tree customization (already included by LazyVim)
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      window = {
        position = "left",
        width = 30,
        mappings = {
          ["<space>"] = "none",
          ["<cr>"] = "open",
          ["<2-LeftMouse>"] = "open",
        },
      },
      filesystem = {
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
        filtered_items = {
          visible = false,
          hide_dotfiles = false,
          hide_gitignored = true,
        },
      },
      event_handlers = {
        {
          event = "neo_tree_buffer_enter",
          handler = function()
            vim.opt_local.signcolumn = "no"
            vim.opt_local.cursorline = true
          end,
        },
      },
    },
  },

  -- Telescope customization (already included by LazyVim)
  {
    "nvim-telescope/telescope.nvim",
    opts = {
      defaults = {
        layout_strategy = "horizontal",
        layout_config = {
          horizontal = {
            preview_width = 0.55,
          },
        },
      },
    },
  },
}
