{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.nvim.enable {
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
    package = unstablePkgs.neovim-unwrapped;
    extraPackages = with pkgs; [
      lua-language-server
      # Nix Language server
      nil

      # HTML, CSS, JSON
      vscode-langservers-extracted

      # LazyVim defaults
      stylua
      shfmt

      # Markdown extra
      nodePackages.markdownlint-cli
      marksman

      # Docker extra
      nodePackages.dockerfile-language-server-nodejs
      hadolint
      docker-compose-language-service

      # JSON and YAML extras
      nodePackages.yaml-language-server

      # Nix formatter
      alejandra

    ];
#    extraLuaPackages = ps: [
#      ps.tiktoken_core
#    ];
     plugins = with unstablePkgs.vimPlugins; [
       vim-sleuth
       gitsigns-nvim
       which-key-nvim
       todo-comments-nvim
       vim-tmux-navigator
       nui-nvim
       fidget-nvim

       # File Tree

       neo-tree-nvim

       # Telescope

       plenary-nvim
       telescope-nvim
       telescope-fzf-native-nvim
       telescope-ui-select-nvim
       nvim-web-devicons

       # Colorscheme

       catppuccin-nvim
       (pkgs.vimUtils.buildVimPlugin {
          pname = "solarized-nvim";
          version = "3.4.0";
          src = pkgs.fetchFromGitHub {
            owner = "maxmx03";
            repo = "solarized.nvim";
            rev = "a6383a31a1326acbf43d7144035b59de5e1a9d1f";
            sha256 = "sha256-beSloeMBXuEIMBobjWgVWGUnjjiu23MZ9hZEZh97/1E=";
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
       nvim-treesitter.withAllGrammars

       # LSP
       nvim-lspconfig

       # Formatter
       conform-nvim

       # Linting
       nvim-lint

       # 
#      telescope-nvim
#      telescope-fzf-native-nvim
#      nvim-treesitter.withAllGrammars
#      lsp-zero-nvim
#      nvim-lspconfig
#      lspcontainers-nvim
#      nvim-cmp
#      cmp-nvim-lsp
#      cmp-nvim-lua
#      cmp_luasnip
#      luasnip
#      friendly-snippets
#      nvim-lastplace
#      ale
#      copilot-lua
#      CopilotChat-nvim
#      copilot-cmp
#      trouble-nvim
#      nvim-web-devicons
#      plenary-nvim
#      nerdtree
#      nerdtree-git-plugin
#      vim-tmux-navigator
#      vim-airline
#      vim-airline-themes
#      nerdcommenter
#      nvim-solarized-lua
#      vim-surround
#      vim-repeat
#      editorconfig-vim
#      vim-polyglot
#      vim-devicons
     ];
  };
}
