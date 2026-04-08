-- Main config setup - loads all subconfigs
local M = {}

function M.setup()
  require("config.options")
  require("config.keymaps")
  require("config.autocmds")
  require("plugins.lsp")
  require("plugins.ai")
  require("plugins.editor")
  require("plugins.git")
  require("plugins.ui")
end

return M
