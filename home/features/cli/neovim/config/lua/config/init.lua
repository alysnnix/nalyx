-- Main config setup - loads all subconfigs

-- Defer loading options to avoid conflicts with lazy installer screen
vim.defer_fn(function()
  pcall(require, "config.options")
end, 100)

require("config.keymaps")
require("config.autocmds")

local ok, mod
ok, mod = pcall(require, "plugins.ui"); if ok and mod and mod.setup then mod:setup() end
ok, mod = pcall(require, "plugins.editor"); if ok and mod and mod.setup then mod:setup() end
ok, mod = pcall(require, "plugins.git"); if ok and mod and mod.setup then mod:setup() end
ok, mod = pcall(require, "plugins.lsp"); if ok and mod and mod.setup then mod:setup() end
ok, mod = pcall(require, "plugins.ai"); if ok and mod and mod.setup then mod:setup() end
