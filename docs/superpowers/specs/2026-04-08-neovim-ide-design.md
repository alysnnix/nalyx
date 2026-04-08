# Neovim IDE Setup - Design Spec

**Date:** 2026-04-08
**Goal:** Replace VS Code/Zed with Neovim as primary editor, configured as a full IDE experience via LazyVim.

## Context

User relies on Claude Code for heavy coding work. The editor serves primarily as a navigation, review, and light editing tool. Current Neovim setup is completely bare — just the package installed with no plugins or configuration.

## Approach: LazyVim Distribution

Use LazyVim as the base distribution, customized with VS Code-style keybindings. Config files live in the Nix repo and are deployed via `xdg.configFile`. LSP servers and tools are installed via Nix packages (Mason disabled) for reproducibility.

## Module Structure

**Nix module:** `home/features/cli/neovim/default.nix`

- Enables `programs.neovim`
- Installs LSP servers, formatters, and dependencies as Nix packages
- Copies Lua config to `~/.config/nvim/` via `xdg.configFile`
- Imported unconditionally in `home/features/cli/default.nix`
- Sets `EDITOR = "nvim"` in sessionVariables

**Lua config structure:**

```
home/features/cli/neovim/
├── default.nix
└── config/
    ├── init.lua                 # Bootstrap lazy.nvim + LazyVim
    ├── lazyvim.json             # LazyVim version/extras
    └── lua/
        ├── config/
        │   ├── keymaps.lua      # VS Code-style keybindings
        │   ├── options.lua      # General options (mouse, line numbers, etc)
        │   └── autocmds.lua     # Custom autocommands
        └── plugins/
            ├── editor.lua       # neo-tree, telescope, toggleterm
            ├── lsp.lua          # LSP config, Mason disabled, per-language setup
            ├── git.lua          # gitsigns, lazygit integration
            ├── ai.lua           # copilot, avante.nvim (optional, lazy-loaded)
            └── ui.lua           # catppuccin, bufferline, lualine customization
```

## Plugins

### Core (always loaded)

| Plugin | Purpose |
|--------|---------|
| LazyVim | Base distribution with sane defaults |
| neo-tree.nvim | File tree sidebar (left), mouse support, click to open |
| telescope.nvim | Fuzzy finder for files, text, commands |
| catppuccin | Color theme (Mocha variant) |
| bufferline.nvim | Tab bar at top (comes with LazyVim) |
| lualine.nvim | Status line at bottom (comes with LazyVim) |
| treesitter | Advanced syntax highlighting for all languages |

### LSP (lazy-loaded by filetype)

| Language | Server | Nix Package |
|----------|--------|-------------|
| TypeScript/JS | ts_ls | nodePackages.typescript-language-server |
| Python | pyright | pyright |
| Go | gopls | gopls |
| Java | jdtls | jdt-language-server |
| Nix | nil | nil |
| LaTeX | texlab | texlab |
| Lua | lua_ls | lua-language-server |

### Formatters (via Nix packages)

| Language | Formatter |
|----------|-----------|
| Nix | nixfmt |
| JS/TS | prettier |
| Python | black |
| Go | gofmt (included with Go) |
| Lua | stylua |
| LaTeX | latexindent |

### Git (lazy-loaded)

| Plugin | Purpose |
|--------|---------|
| gitsigns.nvim | Gutter marks for added/modified/removed lines |
| lazygit.nvim | Opens lazygit inside Neovim (already installed system-wide) |

### AI (lazy-loaded, optional)

| Plugin | Purpose |
|--------|---------|
| copilot.lua | GitHub Copilot inline autocomplete |
| avante.nvim | AI chat sidebar (supports Claude and Copilot) |

### Terminal (lazy-loaded, optional)

| Plugin | Purpose |
|--------|---------|
| toggleterm.nvim | Toggle terminal panel with Alt+Q |

## Keybindings (VS Code style)

| Shortcut | Action |
|----------|--------|
| `Ctrl+S` | Save and format |
| `Ctrl+E` | Find files by name (telescope) |
| `Ctrl+Shift+F` | Search text in project (grep) |
| `Ctrl+P` | Command palette (telescope commands) |
| `Ctrl+B` | Toggle file tree (neo-tree) |
| `Ctrl+\`` | Toggle terminal (alternative) |
| `Alt+Q` | Toggle terminal (toggleterm) |
| `Ctrl+W` | Close current tab/buffer |
| `Ctrl+Tab` | Next tab |
| `Ctrl+Shift+Tab` | Previous tab |
| `Ctrl+Z` | Undo |
| `Ctrl+Shift+Z` | Redo |
| `Ctrl+/` | Toggle comment |
| `Ctrl+D` | Select next occurrence (multi-cursor) |
| `Ctrl+G` | Open lazygit |
| Mouse | Click on file tree, tabs, text selection — all works |

## Nix Integration

- **Mason disabled** — all LSP servers and formatters installed as Nix packages for reproducibility
- **ripgrep and fd** installed as Nix packages (telescope dependencies)
- **Available on all hosts** — imported unconditionally in `home/features/cli/default.nix`
- **EDITOR fixed** — `sessionVariables.EDITOR` changed from `"vim"` to `"nvim"`

## File Preview

- **Code/text files:** Preview in neo-tree split or open in buffer on click
- **PDFs and images:** Open with `xdg-open` (or `wslview` on WSL) in system default app

## Out of Scope

- NixVim (decided against — LazyVim is faster to get working)
- Matugen/Hyprland theme integration (not using Hyprland currently)
- DAP/debugger setup (Claude Code handles debugging workflow)
- Custom snippets (can add later if needed)
