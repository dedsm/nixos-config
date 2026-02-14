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
  '';
  tmuxDarkCustom = pkgs.writeText "solarized-dark-custom.conf" ''
    set -g window-style 'bg=${colors.base02}'
    set -g window-active-style 'bg=${colors.base03}'
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
          ${pkgs.procps}/bin/pkill -USR2 foot || true
        '';
        tmux-theme = ''
          ${pkgs.tmux}/bin/tmux source-file ${solarizedDarkTheme} || true
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
          ${pkgs.procps}/bin/pkill -USR1 foot || true
        '';
        tmux-theme = ''
          ${pkgs.tmux}/bin/tmux source-file ${solarizedLightTheme} || true
        '';
        hyprland-theme = mkIf homeManagerConfig.hyprland.enable ''
          ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border "0xff${builtins.substring 1 6 colors.red}" || true
        '';
      };
    };

    # Neovim: ensure dark-notify is configured to use darkman on Linux
    # (The plugin handles this automatically if darkman is running)
    
    # We can also export these colors as environment variables or files if needed
    home.file.".colorscheme-palette".text = builtins.toJSON colors;
  };
}
