{ lib, pkgs, homeManagerConfig, username, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  homeDir = if isLinux then "/home/${username}" else "/Users/${username}";

  # Base plugins for all systems
  basePlugins = with pkgs.tmuxPlugins; [
    vim-tmux-navigator
  ];

  # Darwin-only plugins
  darwinPlugins = [];

  # Platform-specific terminal configuration
  terminalConfig = if isDarwin then ''
    # True color and OSC passthrough for ghostty
    set-option -ga terminal-overrides ",ghostty:Tc"
    set -g allow-passthrough all
  '' else ''
    # True color for xterm-compatible terminals
    set-option -ga terminal-overrides ",xterm*:Tc"
  '';

  # Theme configuration
  themeConfig = ''
    # Source the managed theme symlink (created/updated by theme scripts)
    if-shell "test -e ${homeDir}/.local/state/tmux/current-theme.conf" \
      "source-file ${homeDir}/.local/state/tmux/current-theme.conf"
  '';
in
with lib;
mkIf (homeManagerConfig.tmux.enable or false) {
  programs.tmux = {
    enable = true;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 0;
    extraConfig = terminalConfig + builtins.readFile ./tmux.conf + themeConfig;
    historyLimit = 30000;
    prefix = "C-f";
    resizeAmount = 5;
    terminal = "screen-256color";
    tmuxinator.enable = true;
    plugins = basePlugins ++ darwinPlugins;
  };
}
