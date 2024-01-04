{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.nvim.enable {
  home = {
    sessionVariables = { EDITOR = "vim"; };
    file = {
      nvim_config = {
        target = ".config/nvim";
        recursive = true;
        source = ./config;
      };
    };
  };
  programs.neovim = {
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = true;
    withPython3 = true;
    withRuby = false;
    enable = true;
    plugins = with pkgs.vimPlugins; [
      telescope-nvim
      telescope-fzf-native-nvim
      nvim-treesitter.withAllGrammars
      unstablePkgs.vimPlugins.lsp-zero-nvim
      unstablePkgs.vimPlugins.nvim-lspconfig
      unstablePkgs.vimPlugins.lspcontainers-nvim
      unstablePkgs.vimPlugins.nvim-cmp
      unstablePkgs.vimPlugins.cmp-nvim-lsp
      unstablePkgs.vimPlugins.cmp-nvim-lua
      unstablePkgs.vimPlugins.cmp_luasnip
      unstablePkgs.vimPlugins.luasnip
      unstablePkgs.vimPlugins.friendly-snippets
      unstablePkgs.vimPlugins.nvim-lastplace
      unstablePkgs.vimPlugins.ale
      unstablePkgs.vimPlugins.copilot-lua
      unstablePkgs.vimPlugins.copilot-cmp
      unstablePkgs.vimPlugins.trouble-nvim
      unstablePkgs.vimPlugins.nvim-web-devicons
      nerdtree
      nerdtree-git-plugin
      vim-tmux-navigator
      vim-airline
      vim-airline-themes
      nerdcommenter
      NeoSolarized
      vim-surround
      vim-repeat
      editorconfig-vim
      vim-polyglot
      vim-devicons
    ];
  };
}
