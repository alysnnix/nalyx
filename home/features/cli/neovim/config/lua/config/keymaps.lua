-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

local map = vim.keymap.set

-- Save and format (Ctrl+S)
map({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

-- Find files (Ctrl+E)
map("n", "<C-e>", "<cmd>Telescope find_files<cr>", { desc = "Find files" })

-- Search text in project (Ctrl+Shift+F)
map("n", "<C-S-f>", "<cmd>Telescope live_grep<cr>", { desc = "Grep project" })

-- Command palette (Ctrl+P)
map("n", "<C-p>", "<cmd>Telescope commands<cr>", { desc = "Command palette" })

-- Toggle file tree (Ctrl+B)
map("n", "<C-b>", "<cmd>Neotree toggle<cr>", { desc = "Toggle file tree" })

-- Toggle terminal (Alt+Q)
map({ "n", "t" }, "<A-q>", function()
  Snacks.terminal.toggle()
end, { desc = "Toggle terminal" })

-- Close buffer (Ctrl+W)
map("n", "<C-w>", "<cmd>bd<cr>", { desc = "Close buffer" })

-- Tab navigation (Ctrl+Tab / Ctrl+Shift+Tab)
map("n", "<C-Tab>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<C-S-Tab>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })

-- Undo/Redo (Ctrl+Z / Ctrl+Shift+Z)
map({ "n", "i" }, "<C-z>", "<cmd>undo<cr>", { desc = "Undo" })
map({ "n", "i" }, "<C-S-z>", "<cmd>redo<cr>", { desc = "Redo" })

-- Toggle comment (Ctrl+/) — uses LazyVim's mini.comment
map("n", "<C-/>", "gcc", { remap = true, desc = "Toggle comment" })
map("v", "<C-/>", "gc", { remap = true, desc = "Toggle comment" })

-- Open lazygit (Ctrl+G)
map("n", "<C-g>", function()
  Snacks.terminal("lazygit", { cwd = LazyVim.root(), esc_esc = false, ctrl_hjkl = false })
end, { desc = "Lazygit" })

-- Git status panel (Alt+2)
map("n", "<A-2>", "<cmd>Neotree git_status toggle<cr>", { desc = "Git status panel" })

-- IDE-style clipboard (Ctrl+C/V/X)
map("v", "<C-c>", '"+y', { desc = "Copy" })
map({ "n", "i" }, "<C-v>", '<C-r>+', { desc = "Paste" })
map("v", "<C-v>", '"+p', { desc = "Paste" })
map("v", "<C-x>", '"+d', { desc = "Cut" })

-- Select all (Ctrl+A)
map("n", "<C-a>", "ggVG", { desc = "Select all" })

-- Visual mode: Shift+arrows to select
map("n", "<S-Up>", "v<Up>", { desc = "Select up" })
map("n", "<S-Down>", "v<Down>", { desc = "Select down" })
map("n", "<S-Left>", "v<Left>", { desc = "Select left" })
map("n", "<S-Right>", "v<Right>", { desc = "Select right" })
map("v", "<S-Up>", "<Up>", { desc = "Extend selection up" })
map("v", "<S-Down>", "<Down>", { desc = "Extend selection down" })
map("v", "<S-Left>", "<Left>", { desc = "Extend selection left" })
map("v", "<S-Right>", "<Right>", { desc = "Extend selection right" })

-- Escape to leave visual mode (already default, but explicit)
map("v", "<Esc>", "<Esc>", { desc = "Exit visual mode" })
