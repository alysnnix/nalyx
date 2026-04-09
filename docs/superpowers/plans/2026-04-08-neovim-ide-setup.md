# Neovim IDE Setup - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure Neovim as a full IDE experience via LazyVim with VS Code-style keybindings, all LSP servers installed via Nix (Mason disabled).

**Architecture:** LazyVim distribution as base, with Lua config files deployed via `xdg.configFile` from the Nix module. Plugins managed by lazy.nvim at runtime (downloaded from GitHub). LSP servers, formatters, and tool dependencies installed as Nix packages for reproducibility.

**Tech Stack:** NixOS, Home-Manager, Neovim, LazyVim, Lua, Treesitter

**Spec:** `docs/superpowers/specs/2026-04-08-neovim-ide-design.md`

---

## File Structure

```
home/features/cli/neovim/
├── default.nix                    # Nix module: packages + xdg.configFile mappings
└── config/
    ├── init.lua                   # Bootstrap lazy.nvim + load LazyVim
    ├── lazyvim.json               # LazyVim version tracking
    └── lua/
        ├── config/
        │   ├── keymaps.lua        # VS Code-style keybindings
        │   ├── options.lua        # General editor options
        │   └── autocmds.lua       # Custom autocommands
        └── plugins/
            ├── editor.lua         # neo-tree, telescope, toggleterm
            ├── lsp.lua            # LSP config, Mason disabled, per-language servers
            ├── git.lua            # gitsigns, lazygit integration
            ├── ai.lua             # copilot, avante.nvim (lazy-loaded)
            └── ui.lua             # catppuccin theme, bufferline, lualine tweaks
```

**Existing files modified:**
- `home/features/cli/neovim/default.nix` — full rewrite (currently 47 lines of inline Lua)

**Existing files NOT modified:**
- `home/default.nix` — already has `EDITOR = "nvim"` at line 47
- `home/features/cli/default.nix` — already imports `./neovim`

---

## Validation Strategy

This is a NixOS configuration project — no unit tests. Validation at each task:

1. **Lua syntax:** `nvim --headless -c "luafile <path>" -c "q"` for each Lua file (catches syntax errors)
2. **Nix validation:** `nix fmt` + `nix flake check --no-build` after the Nix module is updated
3. **Full rebuild:** `switch wsl` at the end to verify everything loads

---

### Task 1: Create init.lua (lazy.nvim bootstrap + LazyVim loader)

**Files:**
- Create: `home/features/cli/neovim/config/init.lua`

- [ ] **Step 1: Create init.lua**

This file bootstraps lazy.nvim from GitHub and loads LazyVim as the base distribution. LazyVim expects a specific setup call with `spec` pointing to the user's plugin directory.

```lua
-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Load LazyVim
require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false,
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
```

- [ ] **Step 2: Create lazyvim.json**

```json
{
  "extras": [],
  "news": {
    "NEWS.md": ""
  },
  "version": 7
}
```

- [ ] **Step 3: Verify Lua syntax**

Run: `nvim --headless -c "luafile home/features/cli/neovim/config/init.lua" -c "q" 2>&1 || echo "syntax check done"`

Expected: No Lua syntax errors (runtime errors about missing modules are OK — lazy.nvim isn't installed yet)

- [ ] **Step 4: Commit**

```bash
git add home/features/cli/neovim/config/init.lua home/features/cli/neovim/config/lazyvim.json
git commit -m "feat(neovim): add init.lua with lazy.nvim bootstrap and LazyVim loader"
```

---

### Task 2: Create options.lua and autocmds.lua

**Files:**
- Create: `home/features/cli/neovim/config/lua/config/options.lua`
- Create: `home/features/cli/neovim/config/lua/config/autocmds.lua`

- [ ] **Step 1: Create options.lua**

LazyVim loads `lua/config/options.lua` automatically before plugins. These options override LazyVim defaults.

```lua
-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

-- General
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.swapfile = false
vim.opt.undofile = true

-- UI
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- Indentation
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- Splits
vim.opt.splitbelow = true
vim.opt.splitright = true

-- Wrapping
vim.opt.wrap = false
```

- [ ] **Step 2: Create autocmds.lua**

LazyVim loads `lua/config/autocmds.lua` automatically. Keep it minimal — LazyVim already has good defaults.

```lua
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
```

- [ ] **Step 3: Verify Lua syntax**

Run: `nvim --headless -c "luafile home/features/cli/neovim/config/lua/config/options.lua" -c "q" 2>&1`
Run: `nvim --headless -c "luafile home/features/cli/neovim/config/lua/config/autocmds.lua" -c "q" 2>&1`

Expected: No Lua syntax errors

- [ ] **Step 4: Commit**

```bash
git add home/features/cli/neovim/config/lua/config/options.lua home/features/cli/neovim/config/lua/config/autocmds.lua
git commit -m "feat(neovim): add editor options and autocmds (binary file opener)"
```

---

### Task 3: Create keymaps.lua (VS Code-style bindings)

**Files:**
- Create: `home/features/cli/neovim/config/lua/config/keymaps.lua`

- [ ] **Step 1: Create keymaps.lua**

LazyVim loads `lua/config/keymaps.lua` automatically. These add VS Code-style bindings on top of LazyVim defaults.

```lua
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
```

- [ ] **Step 2: Verify Lua syntax**

Run: `nvim --headless -c "luafile home/features/cli/neovim/config/lua/config/keymaps.lua" -c "q" 2>&1`

Expected: No Lua syntax errors (runtime errors about Snacks/LazyVim globals are OK — they load at runtime)

- [ ] **Step 3: Commit**

```bash
git add home/features/cli/neovim/config/lua/config/keymaps.lua
git commit -m "feat(neovim): add VS Code-style keybindings"
```

---

### Task 4: Create ui.lua (catppuccin theme + UI tweaks)

**Files:**
- Create: `home/features/cli/neovim/config/lua/plugins/ui.lua`

- [ ] **Step 1: Create ui.lua**

Configure catppuccin as the theme and customize bufferline/lualine appearance. LazyVim already includes bufferline and lualine — we just need to set preferences.

```lua
return {
  -- Catppuccin color scheme
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      integrations = {
        cmp = true,
        gitsigns = true,
        neo_tree = true,
        telescope = { enabled = true },
        treesitter = true,
        native_lsp = {
          enabled = true,
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
          },
        },
      },
    },
  },

  -- Set catppuccin as the colorscheme
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },

  -- Bufferline customization (already included by LazyVim)
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        always_show_bufferline = true,
        separator_style = "thin",
      },
    },
  },

  -- Lualine customization (already included by LazyVim)
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      options = {
        theme = "catppuccin",
      },
    },
  },
}
```

- [ ] **Step 2: Verify Lua syntax**

Run: `nvim --headless -c "luafile home/features/cli/neovim/config/lua/plugins/ui.lua" -c "q" 2>&1`

Expected: Returns a table (no syntax errors)

- [ ] **Step 3: Commit**

```bash
git add home/features/cli/neovim/config/lua/plugins/ui.lua
git commit -m "feat(neovim): add catppuccin theme and UI config"
```

---

### Task 5: Create editor.lua (neo-tree, telescope, toggleterm)

**Files:**
- Create: `home/features/cli/neovim/config/lua/plugins/editor.lua`

- [ ] **Step 1: Create editor.lua**

Neo-tree and telescope are included in LazyVim by default. We customize neo-tree for mouse support and add toggleterm as a new plugin.

```lua
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
```

- [ ] **Step 2: Verify Lua syntax**

Run: `nvim --headless -c "luafile home/features/cli/neovim/config/lua/plugins/editor.lua" -c "q" 2>&1`

Expected: Returns a table (no syntax errors)

- [ ] **Step 3: Commit**

```bash
git add home/features/cli/neovim/config/lua/plugins/editor.lua
git commit -m "feat(neovim): add neo-tree and telescope customization"
```

---

### Task 6: Create lsp.lua (Mason disabled, Nix-managed servers)

**Files:**
- Create: `home/features/cli/neovim/config/lua/plugins/lsp.lua`

- [ ] **Step 1: Create lsp.lua**

Disable Mason entirely (LSP servers are installed via Nix packages and available on PATH). Configure each language server explicitly.

```lua
return {
  -- Disable Mason (LSP servers installed via Nix)
  { "williamboman/mason.nvim", enabled = false },
  { "williamboman/mason-lspconfig.nvim", enabled = false },

  -- LSP configuration
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ts_ls = {},
        pyright = {},
        gopls = {},
        jdtls = {},
        nil_ls = {},
        texlab = {},
        lua_ls = {
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              completion = { callSnippet = "Replace" },
            },
          },
        },
      },
    },
  },

  -- Disable conform.nvim Mason integration, formatters are on PATH via Nix
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        nix = { "nixfmt" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        typescriptreact = { "prettier" },
        javascriptreact = { "prettier" },
        json = { "prettier" },
        html = { "prettier" },
        css = { "prettier" },
        python = { "black" },
        go = { "gofmt" },
        lua = { "stylua" },
        tex = { "latexindent" },
        latex = { "latexindent" },
      },
    },
  },
}
```

- [ ] **Step 2: Verify Lua syntax**

Run: `nvim --headless -c "luafile home/features/cli/neovim/config/lua/plugins/lsp.lua" -c "q" 2>&1`

Expected: Returns a table (no syntax errors)

- [ ] **Step 3: Commit**

```bash
git add home/features/cli/neovim/config/lua/plugins/lsp.lua
git commit -m "feat(neovim): add LSP config with Mason disabled, Nix-managed servers"
```

---

### Task 7: Create git.lua (gitsigns + lazygit)

**Files:**
- Create: `home/features/cli/neovim/config/lua/plugins/git.lua`

- [ ] **Step 1: Create git.lua**

Gitsigns is already included by LazyVim. Lazygit integration is handled via Snacks.terminal in keymaps.lua (Ctrl+G). This file just customizes gitsigns appearance.

```lua
return {
  -- Gitsigns customization (already included by LazyVim)
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = {
        add = { text = "+" },
        change = { text = "~" },
        delete = { text = "_" },
        topdelete = { text = "-" },
        changedelete = { text = "~" },
      },
      current_line_blame = true,
      current_line_blame_opts = {
        delay = 500,
      },
    },
  },
}
```

- [ ] **Step 2: Verify Lua syntax**

Run: `nvim --headless -c "luafile home/features/cli/neovim/config/lua/plugins/git.lua" -c "q" 2>&1`

Expected: Returns a table (no syntax errors)

- [ ] **Step 3: Commit**

```bash
git add home/features/cli/neovim/config/lua/plugins/git.lua
git commit -m "feat(neovim): add gitsigns config with inline blame"
```

---

### Task 8: Create ai.lua (copilot + avante)

**Files:**
- Create: `home/features/cli/neovim/config/lua/plugins/ai.lua`

- [ ] **Step 1: Create ai.lua**

Both plugins are lazy-loaded. Copilot activates on InsertEnter, avante loads on command.

```lua
return {
  -- GitHub Copilot
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = "<Tab>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
      panel = { enabled = false },
    },
  },

  -- Avante.nvim — AI chat sidebar
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    build = "make",
    opts = {
      provider = "copilot",
    },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "zbirenbaum/copilot.lua",
    },
  },
}
```

- [ ] **Step 2: Verify Lua syntax**

Run: `nvim --headless -c "luafile home/features/cli/neovim/config/lua/plugins/ai.lua" -c "q" 2>&1`

Expected: Returns a table (no syntax errors)

- [ ] **Step 3: Commit**

```bash
git add home/features/cli/neovim/config/lua/plugins/ai.lua
git commit -m "feat(neovim): add copilot and avante.nvim AI plugins"
```

---

### Task 9: Rewrite default.nix (Nix module with xdg.configFile)

**Files:**
- Modify: `home/features/cli/neovim/default.nix` (full rewrite)

- [ ] **Step 1: Rewrite default.nix**

Replace the current inline-Lua approach with `xdg.configFile` that sources the config directory. Install all LSP servers, formatters, and dependencies as Nix packages.

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    neovim

    # Telescope dependencies
    ripgrep
    fd

    # LSP servers
    nodePackages.typescript-language-server
    pyright
    gopls
    jdt-language-server
    nil
    texlab
    lua-language-server

    # Formatters
    nixfmt
    nodePackages.prettier
    black
    stylua
    texlivePackages.latexindent

    # Build dependency for avante.nvim
    gcc
    gnumake
  ];

  # Deploy Lua config to ~/.config/nvim/
  xdg.configFile = {
    "nvim/init.lua".source = ./config/init.lua;
    "nvim/lazyvim.json".source = ./config/lazyvim.json;
    "nvim/lua/config/options.lua".source = ./config/lua/config/options.lua;
    "nvim/lua/config/keymaps.lua".source = ./config/lua/config/keymaps.lua;
    "nvim/lua/config/autocmds.lua".source = ./config/lua/config/autocmds.lua;
    "nvim/lua/plugins/ui.lua".source = ./config/lua/plugins/ui.lua;
    "nvim/lua/plugins/editor.lua".source = ./config/lua/plugins/editor.lua;
    "nvim/lua/plugins/lsp.lua".source = ./config/lua/plugins/lsp.lua;
    "nvim/lua/plugins/git.lua".source = ./config/lua/plugins/git.lua;
    "nvim/lua/plugins/ai.lua".source = ./config/lua/plugins/ai.lua;
  };
}
```

- [ ] **Step 2: Format**

Run: `nix fmt home/features/cli/neovim/default.nix`

- [ ] **Step 3: Validate flake**

Run: `nix flake check --no-build`

Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add home/features/cli/neovim/default.nix
git commit -m "feat(neovim): rewrite module with xdg.configFile and full LSP/formatter packages"
```

---

### Task 10: Full validation and rebuild

**Files:** None (validation only)

- [ ] **Step 1: Format all Nix files**

Run: `nix fmt`

- [ ] **Step 2: Run flake check**

Run: `nix flake check --no-build`

Expected: No errors

- [ ] **Step 3: Rebuild system**

Run: `switch wsl` (or `switch` to auto-detect)

Expected: Successful rebuild with no errors

- [ ] **Step 4: Verify Neovim launches**

Run: `nvim --headless -c "echo 'LazyVim loaded'" -c "q"`

Expected: Neovim starts without errors

- [ ] **Step 5: Final commit (if any formatting changes)**

```bash
git add -A
git commit -m "chore(neovim): format and validate full IDE setup"
```
