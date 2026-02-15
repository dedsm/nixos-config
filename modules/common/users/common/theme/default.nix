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
    home.packages = [
      (pkgs.writeShellScriptBin "theme-get" (if isLinux then ''
        ${pkgs.darkman}/bin/darkman get
      '' else ''
        if defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then
          echo "dark"
        else
          echo "light"
        fi
      ''))

      # Unified theme-toggle script
      (pkgs.writeShellScriptBin "theme-toggle" (if isLinux then ''
        ${pkgs.darkman}/bin/darkman toggle
      '' else ''
        osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode'
      ''))
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
          # Signal SIGUSR2 to all foot instances to switch to [colors2] (dark)
          ${pkgs.procps}/bin/pkill -x -USR2 foot || true
        '';
        tmux-theme = ''
          # Update symlink for initial startup
          mkdir -p ~/.local/state/tmux
          ln -sf ${solarizedDarkTheme} ~/.local/state/tmux/current-theme.conf

          # Find all tmux sockets for the current user and update them
          find /run/user/$(id -u) /tmp -maxdepth 3 -name "default" -type s 2>/dev/null | while read sock; do
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
          # Signal SIGUSR1 to all foot instances to switch to [colors] (light)
          ${pkgs.procps}/bin/pkill -x -USR1 foot || true
        '';
        tmux-theme = ''
          # Update symlink for initial startup
          mkdir -p ~/.local/state/tmux
          ln -sf ${solarizedLightTheme} ~/.local/state/tmux/current-theme.conf

          # Find all tmux sockets for the current user and update them
          find /run/user/$(id -u) /tmp -maxdepth 3 -name "default" -type s 2>/dev/null | while read sock; do
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
        ".local/bin/theme-apply-dark" = {
          executable = true;
          text = ''
            #!/bin/bash
            # Update symlink for initial startup
            mkdir -p ~/.local/state/tmux
            ln -sf ${solarizedDarkTheme} ~/.local/state/tmux/current-theme.conf

            # Tmux
            find /tmp -maxdepth 3 -name "default" -type s 2>/dev/null | while read sock; do
              ${pkgs.tmux}/bin/tmux -S "$sock" source-file ${solarizedDarkTheme} || true
            done
          '';
        };
        ".local/bin/theme-apply-light" = {
          executable = true;
          text = ''
            #!/bin/bash
            # Update symlink for initial startup
            mkdir -p ~/.local/state/tmux
            ln -sf ${solarizedLightTheme} ~/.local/state/tmux/current-theme.conf

            # Tmux
            find /tmp -maxdepth 3 -name "default" -type s 2>/dev/null | while read sock; do
              ${pkgs.tmux}/bin/tmux -S "$sock" source-file ${solarizedLightTheme} || true
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
          "${pkgs.unstable.dark-notify}/bin/dark-notify"
          "-c"
          "${homeDir}/.local/bin/theme-apply-dark"
          "-l"
          "${homeDir}/.local/bin/theme-apply-light"
        ];
        RunAtLoad = true;
        KeepAlive = true;
      };
    };

    # Initialize the tmux symlink on activation
    home.activation.initTmuxTheme = let
      themeCheckCmd = if isLinux then 
        ''$(${pkgs.darkman}/bin/darkman get 2>/dev/null)''
      else 
        ''$(defaults read -g AppleInterfaceStyle 2>/dev/null)'';
      darkValue = if isLinux then "dark" else "Dark";
    in ''
      $DRY_RUN_CMD mkdir -p $HOME/.local/state/tmux
      if [[ "${themeCheckCmd}" == "${darkValue}" ]]; then
        $DRY_RUN_CMD ln -sf ${solarizedDarkTheme} $HOME/.local/state/tmux/current-theme.conf
      else
        $DRY_RUN_CMD ln -sf ${solarizedLightTheme} $HOME/.local/state/tmux/current-theme.conf
      fi
    '';
  };
}
