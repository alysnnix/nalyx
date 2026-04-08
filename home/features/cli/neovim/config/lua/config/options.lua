-- General Neovim options - VS Code-like feel
local opt = vim.opt

-- Essential
opt.mouse = "nvic" -- Enable mouse in all modes
opt.clipboard = "unnamedplus" -- Use system clipboard
opt.encoding = "utf-8"

-- UI
opt.number = true -- Line numbers
opt.relativenumber = true -- Relative line numbers
opt.signcolumn = "yes" -- Always show sign column
opt.cursorline = true -- Highlight current line
opt.colorcolumn = "80" -- Column limit marker
opt.wrap = false -- No wrap by default
opt.scrolloff = 8 -- Keep context when scrolling
opt.sidescrolloff = 8
opt.showmode = false -- Don't show mode (bufferline shows it)
opt.showcmd = true -- Show commands in last line
opt.cmdheight = 1 -- Command line height
opt.splitright = true -- Split right by default
opt.splitbelow = true -- Split below by default
opt.laststatus = 3 -- Global statusline
opt.termguicolors = true -- True colors

-- Tabs and indentation
opt.expandtab = true -- Use spaces
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.smartindent = true

-- Search
opt.ignorecase = true -- Case insensitive search
opt.smartcase = true -- Case sensitive if uppercase
opt.hlsearch = true -- Highlight search
opt.incsearch = true -- Incremental search

-- Backup and undo
opt.backup = false
opt.writebackup = false
opt.undofile = true -- Persistent undo
opt.undolevels = 10000
opt.swapfile = false

-- Performance
opt.updatetime = 200 -- Faster updates
opt.timeoutlen = 300 -- Shorter timeout for key sequences
opt.redrawtime = 1500
opt.ttimeoutlen = 10

-- Files
opt.fileencoding = "utf-8"
opt.hidden = true -- Allow unsaved buffers
opt.autoread = true -- Auto read file changes
opt.bufhidden = "wipe" -- Wipe buffer when hidden

-- Fold
opt.foldmethod = "expr"
opt.foldexpr = "nvim_treesitter#foldexpr()"
opt.foldenable = false
opt.foldlevel = 99
