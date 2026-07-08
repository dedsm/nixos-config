# Neovim setup

Module: [`modules/common/users/common/nvim/`](../modules/common/users/common/nvim/) · toggle: `nvim.enable` (on by default in `davidShared`).

## Shape

This is a hand-rolled config, not a distribution (no LazyVim/AstroNvim/etc.) — `programs.neovim` (Home Manager) wraps `neovim-unwrapped` with all plugins declared directly in `default.nix`'s `plugins` list. There's no in-editor plugin manager (no `lazy.nvim`); Nix *is* the plugin manager, so every plugin is either an `nixpkgs` `vimPlugins.*` derivation or pinned explicitly with `buildVimPlugin` + `fetchFromGitHub` (e.g. `solarized-nvim`, `dark-notify`). Bumping a plugin means bumping the `nixpkgs`/`unstable` input or the pinned `rev`/`sha256` — there's no lockfile to run.

Lua config lives under `config/` and is symlinked wholesale into `~/.config/nvim` (`xdg.configFile.nvim.source = ./config`). `config/init.lua` sets core options (leader key `\`, undo/backup behavior, UI tweaks) then `require()`s each `config.*` module in order — see the bottom of `init.lua` for the load order (mappings → neo_tree → telescope → fidget → conform → mini → colorschemes → lint → treesitter → diagnostics → lsp → cmp → claude-code).

## What's wired up

- **LSP**: `nvim-lspconfig`, with per-language server config split into `config/lua/config/lsp/servers/` (`docker.lua`, `frontend.lua`, `luals.lua`, `markdown.lua`, `python.lua`, `ruby.lua`). Server *binaries* are Nix packages listed in `extraPackages` (`lua-language-server`, `vscode-langservers-extracted`, `typescript-language-server`, `dockerfile-language-server`, `yaml-language-server`, `marksman`, ...) rather than installed by an in-editor tool like Mason.
- **Formatting**: `conform-nvim`, backed by `nixfmt`/`alejandra` (Nix), `stylua`, `shfmt`, `markdownlint-cli2`, all provided as Nix packages.
- **Linting**: `nvim-lint`, plus `hadolint`, `docker-compose-language-service`.
- **Fuzzy finding / file tree**: `telescope-nvim` (+ `fzf-native`, `ui-select`), `neo-tree-nvim`.
- **Syntax**: `nvim-treesitter.withAllGrammars` (all grammars vendored via Nix, no runtime `:TSInstall`).
- **Completion**: `nvim-cmp` + `luasnip`/`cmp-nvim-lsp`/`cmp-path`, `lazydev-nvim` for Lua/Neovim API completion.
- **Colorschemes**: `catppuccin-nvim` and a pinned `solarized.nvim`, switched via `config/lua/config/colorschemes.lua`; see `dark-notify` below for how light/dark switching is wired to the OS.
- **Claude Code**: `claude-code-nvim`, configured in `config/lua/config/claude-code.lua` as a vertical split (`<leader>cc` toggles it, `<leader>cR` opens the resume picker). Details on the Claude Code side: [`claude-code.md`](./claude-code.md).
- **Light/dark sync**: a pinned `dark-notify` plugin reacts to the OS appearance — `dark-notify` binary on Darwin, `darkman` on Linux (see the `theme` home-manager module) — and flips the colorscheme automatically.
- **Misc quality-of-life**: `gitsigns-nvim`, `which-key-nvim`, `todo-comments-nvim`, `vim-tmux-navigator` (pane navigation shared with tmux), `vim-lastplace`, `vim-sleuth`, `mini-nvim`, `fidget-nvim` (LSP progress UI).

## Adding a plugin

Add it to the `plugins` list in `modules/common/users/common/nvim/default.nix` (from `pkgs.unstable.vimPlugins.*` if available, otherwise a `buildVimPlugin`/`fetchFromGitHub` pin like `solarized-nvim`), then add or extend a `config/lua/config/*.lua` module and `require()` it from `init.lua` if it needs setup.
