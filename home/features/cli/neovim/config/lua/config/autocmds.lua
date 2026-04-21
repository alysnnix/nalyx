-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

-- Open PDFs and images with system viewer instead of inside Neovim
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = { "*.pdf", "*.png", "*.jpg", "*.jpeg", "*.gif", "*.bmp", "*.svg" },
  callback = function(ev)
    local file = ev.file
    local open_cmd = vim.fn.has("wsl") == 1 and "wslview" or "xdg-open"
    vim.fn.jobstart({ open_cmd, file }, { detach = true })
    -- Close the buffer that was opened for the binary file
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(ev.buf) then
        vim.api.nvim_buf_delete(ev.buf, { force = true })
      end
    end, 100)
  end,
})
