-- VS Code-style keybindings
local map = vim.keymap.set
local opts = { noremap = true, silent = true }

-- Leader key (Space)
vim.g.mapleader = " "

-- Save and format
map("n", "<C-s>", "<Cmd>w<CR>", opts) -- Save
map("n", "<C-S-s>", "<Cmd>wa | wq<CR>", opts) -- Save all and quit

-- File finding
map("n", "<C-e>", "<Cmd>Neotree toggle<CR>", opts) -- File tree (Ctrl+E)
map("n", "<C-b>", "<Cmd>Neotree toggle<CR>", opts) -- File tree (Ctrl+B)
map("n", "<C-p>", "<Cmd>Telescope find_files<CR>", opts) -- Find files
map("n", "<C-S-f>", "<Cmd>Telescope live_grep<CR>", opts) -- Search in files

-- Terminal
map("n", "<A-q>", "<Cmd>ToggleTerm<CR>", opts) -- Toggle terminal (Alt+Q)
map("n", "<C-`>", "<Cmd>ToggleTerm<CR>", opts) -- Toggle terminal (Ctrl+`)

-- Git
map("n", "<C-g>", "<Cmd>LazyGit<CR>", opts) -- Open lazygit
map("n", "<C-S-g>", "<Cmd>LazyGitCurrentFile<CR>", opts) -- Lazygit for current file

-- Tabs and buffers
map("n", "<C-w>", "<Cmd>bdelete<CR>", opts) -- Close buffer
map("n", "<C-W>", "<Cmd>bdelete!<CR>", opts) -- Force close buffer
map("n", "<C-Tab>", "<Cmd>BufferLineCycleNext<CR>", opts) -- Next tab
map("n", "<C-S-Tab>", "<Cmd>BufferLineCyclePrev<CR>", opts) -- Previous tab

-- Undo/Redo
map("n", "<C-z>", "<Cmd>undo<CR>", opts) -- Undo
map("n", "<C-S-z>", "<Cmd>redo<CR>", opts) -- Redo

-- Editing
map("n", "<C-d>", "<Cmd>normal! m`vy<CR>`<<CR>", opts) -- Multi-cursor (select next)
map("i", "<C-d>", "<Esc>yviw", opts) -- Multi-cursor insert mode
map("n", "<C-/>", "<Cmd>normal! gcc<CR>", opts) -- Toggle comment
map("v", "<C-/>", "gc", opts) -- Toggle comment in visual

-- Window navigation
map("n", "<C-h>", "<C-w>h", opts) -- Move to left window
map("n", "<C-j>", "<C-w>j", opts) -- Move to down window
map("n", "<C-k>", "<C-w>k", opts) -- Move to up window
map("n", "<C-l>", "<C-w>l", opts) -- Move to right window

-- Resize windows
map("n", "<C-Up>", "<Cmd>resize +2<CR>", opts)
map("n", "<C-Down>", "<Cmd>resize -2<CR>", opts)
map("n", "<C-Left>", "<Cmd>vertical resize -2<CR>", opts)
map("n", "<C-Right>", "<Cmd>vertical resize +2<CR>", opts)

-- Command palette
map("n", "<C-S-p>", "<Cmd>Telescope commands<CR>", opts)

-- LSP
map("n", "gd", "<Cmd>Telescope lsp_definitions<CR>", opts) -- Go to definition
map("n", "gr", "<Cmd>Telescope lsp_references<CR>", opts) -- Find references
map("n", "gi", "<Cmd>Telescope lsp_implementations<CR>", opts) -- Find implementations
map("n", "K", vim.lsp.buf.hover, opts) -- Hover docs
map("n", "<C-Space>", vim.lsp.buf.completion, opts) -- Trigger completion

-- Debug (for when Claude Code uses it)
map("n", "<F5>", "<Cmd> DapToggleBreakpoint<CR>", opts)
map("n", "<F10>", "<Cmd>DapStepOver<CR>", opts)
map("n", "<F11>", "<Cmd>DapStepInto<CR>", opts)
map("n", "<F12>", "<Cmd>DapStepOut<CR>", opts)

-- Stay in indent with arrow keys in visual mode
map("v", "<", "<gv", opts)
map("v", ">", ">gv", opts)
