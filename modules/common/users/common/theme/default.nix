{
  lib,
  pkgs,
  homeManagerConfig,
  username,
  ...
}:
with lib;
let
  cfg = homeManagerConfig.theme or { enable = false; };
  isLinux = pkgs.stdenv.isLinux;
  homeDir = if isLinux then "/home/${username}" else "/Users/${username}";

  # Solarized Palette
  colors = {
    base03 = "#002b36";
    base02 = "#073642";
    base01 = "#586e75";
    base00 = "#657b83";
    base0 = "#839496";
    base1 = "#93a1a1";
    base2 = "#eee8d5";
    base3 = "#fdf6e3";
    yellow = "#b58900";
    orange = "#cb4b16";
    red = "#dc322f";
    magenta = "#d33682";
    violet = "#6c71c4";
    blue = "#268bd2";
    cyan = "#2aa198";
    green = "#859900";
  };

  # Helper for tmux theme paths (shared with tmux module logic)
  solarizedPlugin = pkgs.tmuxPlugins.tmux-colors-solarized;
  solarizedBaseLightTheme = "${solarizedPlugin}/share/tmux-plugins/tmuxcolors/tmuxcolors-light.conf";
  solarizedBaseDarkTheme = "${solarizedPlugin}/share/tmux-plugins/tmuxcolors/tmuxcolors-dark.conf";

  # Custom tmux overlays (mirrored from tmux/default.nix)
  tmuxLightCustom = pkgs.writeText "solarized-light-custom.conf" ''
    set -g window-style 'bg=${colors.base2}'
    set -g window-active-style 'bg=${colors.base3}'
    set -g status-style fg=${colors.base01},bg=${colors.base2}
    set -g window-status-current-style fg=${colors.orange},bg=${colors.base3}
  '';
  tmuxDarkCustom = pkgs.writeText "solarized-dark-custom.conf" ''
    set -g window-style 'bg=${colors.base02}'
    set -g window-active-style 'bg=${colors.base03}'
    set -g status-style fg=${colors.base1},bg=${colors.base02}
    set -g window-status-current-style fg=${colors.orange},bg=${colors.base03}
  '';

  solarizedLightTheme = pkgs.writeText "solarized-light-combined.conf" ''
    source-file ${solarizedBaseLightTheme}
    source-file ${tmuxLightCustom}
  '';
  solarizedDarkTheme = pkgs.writeText "solarized-dark-combined.conf" ''
    source-file ${solarizedBaseDarkTheme}
    source-file ${tmuxDarkCustom}
  '';

in {
  options.homeManagerConfig.theme = {
    enable = mkEnableOption "automatic dark/light mode toggling";
  };

  config = mkIf cfg.enable {
    # Unified theme-get script
    home.packages = mkIf isLinux [
      (pkgs.writeShellScriptBin "theme-get" ''
        ${pkgs.darkman}/bin/darkman get
      '')
      (pkgs.writeShellScriptBin "theme-toggle" ''
        ${pkgs.darkman}/bin/darkman toggle
      '')
    ];

    # Linux-specific: Darkman for automation
    services.darkman = mkIf isLinux {
      enable = true;
      settings = {
        usegeoclue = true;
      };
      
      # Scripts to execute on transition
      darkModeScripts = {
        gtk-theme = ''
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita-dark'"
        '';
        foot-theme = ''
          # foot: SIGUSR1 switches to [colors-dark] (dark)
          ${pkgs.procps}/bin/pkill -x -USR1 foot || true
        '';
        tmux-theme = ''
          # Update symlink for initial startup
          ${pkgs.coreutils}/bin/mkdir -p $HOME/.local/state/tmux
          ${pkgs.coreutils}/bin/ln -sf ${solarizedDarkTheme} $HOME/.local/state/tmux/current-theme.conf

          # Find all tmux sockets for the current user and update them
          ${pkgs.findutils}/bin/find /run/user/$(id -u) /tmp -maxdepth 3 -name "default" -type s 2>/dev/null | while read sock; do
            ${pkgs.tmux}/bin/tmux -S "$sock" source-file ${solarizedDarkTheme} || true
          done
        '';
        hyprland-theme = mkIf homeManagerConfig.hyprland.enable ''
          ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border "0xff${builtins.substring 1 6 colors.blue}" || true
        '';
      };

      lightModeScripts = {
        gtk-theme = ''
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
          ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita'"
        '';
        foot-theme = ''
          # foot: SIGUSR2 switches to [colors-light] (light)
          ${pkgs.procps}/bin/pkill -x -USR2 foot || true
        '';
        tmux-theme = ''
          # Update symlink for initial startup
          ${pkgs.coreutils}/bin/mkdir -p $HOME/.local/state/tmux
          ${pkgs.coreutils}/bin/ln -sf ${solarizedLightTheme} $HOME/.local/state/tmux/current-theme.conf

          # Find all tmux sockets for the current user and update them
          ${pkgs.findutils}/bin/find /run/user/$(id -u) /tmp -maxdepth 3 -name "default" -type s 2>/dev/null | while read sock; do
            ${pkgs.tmux}/bin/tmux -S "$sock" source-file ${solarizedLightTheme} || true
          done
        '';
        hyprland-theme = mkIf homeManagerConfig.hyprland.enable ''
          ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border "0xff${builtins.substring 1 6 colors.red}" || true
        '';
      };
    };

    # Neovim: ensure dark-notify is configured to use darkman on Linux
    # (The plugin handles this automatically if darkman is running)
    
    # We can also export these colors as environment variables or files if needed
    home.file = mkMerge [
      {
        ".colorscheme-palette".text = builtins.toJSON colors;
      }
      (mkIf (!isLinux) {
        ".local/bin/theme-apply" = {
          executable = true;
          text = ''
            #!/bin/bash
            # Called by dark-notify with "dark" or "light" as $1
            MODE="$1"
            ${pkgs.coreutils}/bin/mkdir -p $HOME/.local/state/tmux

            if [ "$MODE" = "dark" ]; then
              THEME="${solarizedDarkTheme}"
            else
              THEME="${solarizedLightTheme}"
            fi

            # Update symlink for tmux startup
            ${pkgs.coreutils}/bin/ln -sf "$THEME" $HOME/.local/state/tmux/current-theme.conf

            # Reload all running tmux sessions (/private/tmp because Nix find doesn't follow /tmp symlink on macOS)
            ${pkgs.findutils}/bin/find /private/tmp -maxdepth 3 -name "default" -type s 2>/dev/null | while read sock; do
              ${pkgs.tmux}/bin/tmux -S "$sock" source-file "$THEME" || true
            done
          '';
        };
      })
    ];

    # Launch dark-notify on Darwin
    launchd.agents.dark-notify = mkIf (!isLinux) {
      enable = true;
      config = {
        ProgramArguments = [
          "/opt/homebrew/bin/dark-notify"
          "-c"
          "${homeDir}/.local/bin/theme-apply"
        ];
        RunAtLoad = true;
        KeepAlive = true;
      };
    };

    # Initialize the tmux symlink on activation
    home.activation.initTmuxTheme = ''
      $DRY_RUN_CMD mkdir -p $HOME/.local/state/tmux
      if ${if isLinux then "${pkgs.darkman}/bin/darkman get 2>/dev/null | grep -q dark" else ''[[ "$(/usr/bin/defaults read -g AppleInterfaceStyle 2>/dev/null)" == "Dark" ]]''}; then
        $DRY_RUN_CMD ln -sf ${solarizedDarkTheme} $HOME/.local/state/tmux/current-theme.conf
      else
        $DRY_RUN_CMD ln -sf ${solarizedLightTheme} $HOME/.local/state/tmux/current-theme.conf
      fi
    '';
  };
}
