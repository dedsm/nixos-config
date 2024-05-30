{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.nvim.enable {
  home = {
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
    defaultEditor = true;
    package = unstablePkgs.neovim-unwrapped;
    extraLuaPackages = ps: [
      ps.tiktoken_core
    ];
    plugins = with unstablePkgs.vimPlugins; [
      telescope-nvim
      telescope-fzf-native-nvim
      nvim-treesitter.withAllGrammars
      lsp-zero-nvim
      nvim-lspconfig
      lspcontainers-nvim
      nvim-cmp
      cmp-nvim-lsp
      cmp-nvim-lua
      cmp_luasnip
      luasnip
      friendly-snippets
      nvim-lastplace
      ale
      copilot-lua
      CopilotChat-nvim
      copilot-cmp
      trouble-nvim
      nvim-web-devicons
      plenary-nvim
      nerdtree
      nerdtree-git-plugin
      vim-tmux-navigator
      vim-airline
      vim-airline-themes
      nerdcommenter
      nvim-solarized-lua
      vim-surround
      vim-repeat
      editorconfig-vim
      vim-polyglot
      vim-devicons
    ];
  };
}
