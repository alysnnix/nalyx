-- Custom autocommands
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- General autocmds group
local general = augroup("General", {})

-- Highlight on yank
autocmd("TextYankPost", {
  group = general,
  pattern = "*",
  callback = function()
    vim.highlight.on_yank { higroup = "IncSearch", timeout = 200 }
  end,
})

-- Remove trailing whitespace on save
autocmd("BufWritePre", {
  group = general,
  pattern = "*",
  callback = function()
    local view = vim.fn.winsaveview()
    vim.cmd [[keeppatterns %s/\s\+$//e]]
    vim.fn.winrestview(view)
  end,
})

-- Auto-resize splits on window resize
autocmd("VimResized", {
  group = general,
  pattern = "*",
  callback = function()
    vim.cmd "wincmd ="
  end,
})

-- Close certain filetypes with q
autocmd("FileType", {
  group = general,
  pattern = { "qf", "help", "man", "lspinfo", "spectre_panel" },
  callback = function(event)
    vim.bo[event.buf].bufhidden = "wipe"
    vim.keymap.set("n", "q", "<Cmd>bdelete<CR>", { buffer = event.buf, silent = true })
  end,
})

-- Open lazygit floating window at startup
vim.api.nvim_create_autocmd("User", {
  pattern = "LazyGitFloatingWindowOpened",
  group = augroup("LazyGitFloat", {}),
  callback = function()
    vim.keymap.set("n", "q", "<Cmd>LazyGitClose<CR>", { silent = true })
  end,
})

-- Terminal related
autocmd("TermOpen", {
  group = augroup("Terminal", {}),
  pattern = "*",
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.foldcolumn = "0"
    vim.keymap.set("n", "q", "<Cmd>bdelete<CR>", { buffer = 0, silent = true })
  end,
})

-- Remember last cursor position when reopening files
autocmd("BufReadPost", {
  group = general,
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Check if file changed outside of nvim
autocmd({ "BufEnter", "CursorHold", "CursorHoldI" }, {
  group = general,
  pattern = "*",
  callback = function()
    local cmdtype = (vim.fn.has("nvim-0.10") == 1) and vim.fn.getcmdtype() or ""
    if cmdtype == "" then
      vim.cmd "checktime"
    end
  end,
})
