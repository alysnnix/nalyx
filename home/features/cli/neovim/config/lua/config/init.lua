-- Main config setup - loads all subconfigs

require("config.options")
require("config.keymaps")
require("config.autocmds")

pcall(require, "plugins.ui").setup()
pcall(require, "plugins.editor").setup()
pcall(require, "plugins.git").setup()
pcall(require, "plugins.lsp").setup()
pcall(require, "plugins.ai").setup()
