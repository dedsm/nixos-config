{ lib, pkgs, homeManagerConfig, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;

  # Custom tmux-dark-notify plugin with patched paths for homebrew
  tmux-dark-notify = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "dark-notify";
    rtpFilePath = "main.tmux";
    version = "unstable-2024-06-12";
    src = pkgs.fetchFromGitHub {
      owner = "erikw";
      repo = "tmux-dark-notify";
      rev = "v0.1.1";
      sha256 = "sha256-naOIotyAgUHZ2qSPmvLMkxGeU0/vfQYrFPjO7Coig0g=";
    };
    postInstall = ''
      # Patch the runner script to use full path to brew
      substituteInPlace $out/share/tmux-plugins/dark-notify/scripts/tmux-dark-notify-runner.sh \
        --replace 'program_is_in_path brew' 'test -x /opt/homebrew/bin/brew' \
        --replace 'eval "$(brew shellenv)"' 'eval "$(/opt/homebrew/bin/brew shellenv)"'

      # Patch the while loop to exit when tmux server is no longer running
      substituteInPlace $out/share/tmux-plugins/dark-notify/scripts/tmux-dark-notify-runner.sh \
        --replace 'while :; do' 'while tmux list-sessions >/dev/null 2>&1; do'

      # Patch main.tmux to properly detach the runner process
      substituteInPlace $out/share/tmux-plugins/dark-notify/main.tmux \
        --replace '$RUNNER &' 'nohup $RUNNER >/dev/null 2>&1 &'
    '';
  };

  # Solarized themes with custom pane styling overlays
  solarizedPlugin = pkgs.tmuxPlugins.tmux-colors-solarized;
  solarizedBaseLightTheme = "${solarizedPlugin}/share/tmux-plugins/tmuxcolors/tmuxcolors-light.conf";
  solarizedBaseDarkTheme = "${solarizedPlugin}/share/tmux-plugins/tmuxcolors/tmuxcolors-dark.conf";

  solarizedLightTheme = pkgs.writeText "solarized-light-combined.conf" ''
    source-file ${solarizedBaseLightTheme}
    source-file ${./solarized-light-custom.conf}
  '';
  solarizedDarkTheme = pkgs.writeText "solarized-dark-combined.conf" ''
    source-file ${solarizedBaseDarkTheme}
    source-file ${./solarized-dark-custom.conf}
  '';

  # Base plugins for all systems
  basePlugins = with pkgs.tmuxPlugins; [
    vim-tmux-navigator
  ];

  # Darwin-only plugins with extraConfig that loads BEFORE the plugin
  darwinPlugins = if isDarwin then [
    {
      plugin = tmux-dark-notify;
      extraConfig = ''
        # tmux-dark-notify configuration (must be set before plugin loads)
        set -g @dark-notify-theme-path-light '${solarizedLightTheme}'
        set -g @dark-notify-theme-path-dark '${solarizedDarkTheme}'
      '';
    }
  ] else [];

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
  themeConfig = if isDarwin then ''
    # Fallback: source the theme symlink created by dark-notify (needed for initial load)
    if-shell "test -e ~/.local/state/tmux/tmux-dark-notify-theme.conf" \
      "source-file ~/.local/state/tmux/tmux-dark-notify-theme.conf"
  '' else ''
    # Check current theme on startup via unified theme-get script
    if-shell '[ "$(theme-get)" = "dark" ]' \
      'source-file ${solarizedDarkTheme}' \
      'source-file ${solarizedLightTheme}'
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
