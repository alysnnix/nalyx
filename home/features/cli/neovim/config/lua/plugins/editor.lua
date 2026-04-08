-- Editor plugins: neo-tree, telescope, toggleterm
local M = {}

function M.setup()
  -- Neo-tree
  vim.keymap.set("n", "<C-e>", "<Cmd>Neotree toggle<CR>", { desc = "Toggle file tree" })
  vim.keymap.set("n", "<C-b>", "<Cmd>Neotree toggle<CR>", { desc = "Toggle file tree" })
  vim.keymap.set("n", "<leader>e", "<Cmd>Neotree reveal<CR>", { desc = "Reveal current file" })

  -- Telescope
  local ok_telescope, telescope = pcall(require, "telescope")
  if ok_telescope then
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
          "target",
          "dist",
          ".next",
          ".cache",
        },
      },
      pickers = {
        find_files = { theme = "dropdown", previewer = false },
      },
    })
    pcall(telescope.load_extension, "fzf")
  end

  -- ToggleTerm
  local ok_toggleterm, toggleterm = pcall(require, "toggleterm")
  if ok_toggleterm then
    toggleterm.setup({
      size = 15,
      open_mapping = [[<A-q>]],
      direction = "horizontal",
    })
  end

  -- Lazygit
  vim.keymap.set("n", "<C-g>", "<Cmd>LazyGit<CR>", { desc = "Open lazygit" })
end

return M
