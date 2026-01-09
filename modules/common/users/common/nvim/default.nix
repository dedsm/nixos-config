{
  lib,
  homeManagerConfig,

  pkgs,
  ...
}:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
with lib;
  mkIf (homeManagerConfig.nvim.enable or false) {
    xdg.configFile.nvim = {
      recursive = true;
      source = ./config;
    };
    programs.neovim = {
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      withNodeJs = true;
      withPython3 = true;
      withRuby = false;
      enable = true;
      defaultEditor = true;
      package = pkgs.neovim-unwrapped;
      extraPackages = with pkgs; [
        pkgs.unstable.lua-language-server
        # Nix Language server
        nil

        # HTML, CSS, JSON
        pkgs.unstable.vscode-langservers-extracted

        # LazyVim defaults
        stylua
        shfmt

        # Markdown extra
        nodePackages.markdownlint-cli
        marksman

        # Docker extra
        pkgs.unstable.nodePackages.typescript-language-server
        pkgs.dockerfile-language-server
        hadolint
        docker-compose-language-service

        # JSON and YAML extras
        nodePackages.yaml-language-server

        # Nix formatter
        alejandra

        # Tree-sitter CLI for nvim-treesitter
        tree-sitter
      ];
      #    extraLuaPackages = ps: [
      #      ps.tiktoken_core
      #    ];
      plugins = with pkgs.unstable.vimPlugins; [
        vim-sleuth
        gitsigns-nvim
        which-key-nvim
        todo-comments-nvim
        vim-tmux-navigator
        nui-nvim
        fidget-nvim

        # async helpers for nvim plugins
        plenary-nvim

        # File Tree

        neo-tree-nvim

        # Telescope

        plenary-nvim
        telescope-nvim
        telescope-fzf-native-nvim
        telescope-ui-select-nvim
        pkgs.unstable.nixfmt
        nvim-web-devicons

        # Colorscheme

        catppuccin-nvim
        (pkgs.vimUtils.buildVimPlugin {
          pname = "solarized-nvim";
          version = "3.6.0";
          src = pkgs.fetchFromGitHub {
            owner = "maxmx03";
            repo = "solarized.nvim";
            rev = "v3.6.0";
            sha256 = "sha256-fNytlDlYHqX1W1pqt8xLoud+AtMQDlmtUkbwZArj4bs=";
          };
          meta.homepage = "https://github.com/maxmx03/solarized.nvim/";
        })

        # Autocompletion

        nvim-cmp
        luasnip
        cmp_luasnip
        cmp-nvim-lsp
        cmp-path

        luvit-meta
        lazydev-nvim

        # small one-purpose plugins

        mini-nvim

        # Syntax coloring
        pkgs.unstable.vimPlugins.nvim-treesitter.withAllGrammars

        # LSP
        nvim-lspconfig

        # Formatter
        conform-nvim

        # Linting
        nvim-lint

        # open files at last edit position
        vim-lastplace

        # Claude Code integration
        pkgs.unstable.vimPlugins.claude-code-nvim
      ] ++ lib.optionals isDarwin [
        # dark-notify neovim plugin (uses dark-notify binary from homebrew)
        (pkgs.vimUtils.buildVimPlugin {
          pname = "dark-notify";
          version = "0.1.3";
          src = pkgs.fetchFromGitHub {
            owner = "cormacrelf";
            repo = "dark-notify";
            rev = "v0.1.3";
            sha256 = "sha256-TZuuXeolzx3kby2qO9e/FTf+1g39gKk9NzXQxmjN/UA=";
          };
          meta.homepage = "https://github.com/cormacrelf/dark-notify";
        })
      ];
    };
  }
