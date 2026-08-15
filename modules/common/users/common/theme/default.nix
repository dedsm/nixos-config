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

  # The two dconf keys every portal-aware app ultimately reads: xdg-desktop-portal-gtk
  # exposes them over org.freedesktop.portal.Settings, and Firefox/Electron follow that.
  # Nothing else in this repo may declare them statically — see the note in
  # modules/common/users/common/defaults/common/default.nix.
  # `run` is "" for darkman's own scripts and "$DRY_RUN_CMD …" from activation scripts.
  # `|| true` matters on the activation path: home-manager activation runs under
  # `set -eu`, and a theme write that can't reach a bus must not fail the whole rebuild.
  gtkModeSettings = run: scheme: theme: ''
    ${run} ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'${scheme}'" || true
    ${run} ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'${theme}'" || true
  '';
  gtkDarkSettings = gtkModeSettings "" "prefer-dark" "Adwaita-dark";
  gtkLightSettings = gtkModeSettings "" "prefer-light" "Adwaita";

  # darkman persists the active mode here, so activation scripts can learn it without a
  # session bus (`darkman get` is a D-Bus call, and home-manager-<user>.service runs with
  # no DBUS_SESSION_BUS_ADDRESS — it would fail there and silently read as light).
  darkmanModeFile = "\${XDG_CACHE_HOME:-$HOME/.cache}/darkman/mode.txt";
  isDarkNow = ''[ "$(${pkgs.coreutils}/bin/cat "${darkmanModeFile}" 2>/dev/null)" = "dark" ]'';

  # Two things had to be fixed here for the border colour to actually follow the theme:
  #
  #  * darkman's transition scripts are spawned by the systemd user manager, which never
  #    inherited HYPRLAND_INSTANCE_SIGNATURE from the compositor's session — a bare
  #    hyprctl call just logged "is hyprland running?" and did nothing. Recover the
  #    signature from the runtime dir instead.
  #  * Since the 0.55 lua-config migration (`configType = "lua"` in the hyprland module)
  #    `hyprctl keyword` is refused outright with "keyword can't work with non-legacy
  #    parsers. Use eval." — so drive the same option through `hyprctl eval` instead.
  #    That applies live; it needs no reload and no companion file in ~/.config/hypr.
  hyprlandBorder = color: ''
    for instance in "$XDG_RUNTIME_DIR"/hypr/*/; do
      [ -S "$instance/.socket.sock" ] || continue
      HYPRLAND_INSTANCE_SIGNATURE="$(${pkgs.coreutils}/bin/basename "$instance")" \
        ${pkgs.hyprland}/bin/hyprctl eval \
          'hl.config({ general = { col = { active_border = "rgb(${builtins.substring 1 6 color})" } } })' || true
    done
  '';

in
{
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
        gtk-theme = gtkDarkSettings;
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
        hyprland-theme = mkIf homeManagerConfig.hyprland.enable (hyprlandBorder colors.blue);
      };

      lightModeScripts = {
        gtk-theme = gtkLightSettings;
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
        hyprland-theme = mkIf homeManagerConfig.hyprland.enable (hyprlandBorder colors.red);
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
      if ${
        if isLinux then
          isDarkNow
        else
          ''[[ "$(/usr/bin/defaults read -g AppleInterfaceStyle 2>/dev/null)" == "Dark" ]]''
      }; then
        $DRY_RUN_CMD ln -sf ${solarizedDarkTheme} $HOME/.local/state/tmux/current-theme.conf
      else
        $DRY_RUN_CMD ln -sf ${solarizedLightTheme} $HOME/.local/state/tmux/current-theme.conf
      fi
    '';

    # home-manager's `dconf load` runs on every activation, and its dconf-cleanup pass
    # resets keys that a generation stopped managing back to their (light) schema
    # defaults. Either one bumps the dconf shm invalidation flag, so live apps re-read
    # the light value the next time they repaint — which is why a mid-afternoon rebuild
    # used to knock Firefox/Slack back to light minutes after darkman had switched them.
    # Re-assert the mode darkman actually wants, ordered after home-manager's own write.
    # NOTE: the DAG entry is spelled out rather than built with `lib.hm.dag.entryAfter`.
    # modules/common/default.nix `import`s these files with the NixOS `lib`, so the
    # home-manager extensions (`lib.hm`) are not in scope here.
    home.activation.reassertColorScheme = mkIf isLinux {
      after = [ "dconfSettings" ];
      before = [ ];
      data = ''
        # `dconf write` needs a session bus. home-manager-<user>.service has none, so
        # prefer the live user bus when the session is up — writing on the real bus lets
        # xdg-desktop-portal-gtk emit SettingChanged and apps repaint immediately instead
        # of waiting for their next dconf read. Fall back to a throwaway bus otherwise
        # (the write still lands in the database, which is what matters at boot).
        reassertBus=""
        if [ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
          if [ -S "/run/user/$(${pkgs.coreutils}/bin/id -u)/bus" ]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(${pkgs.coreutils}/bin/id -u)/bus"
          else
            reassertBus="${pkgs.dbus}/bin/dbus-run-session --dbus-daemon=${pkgs.dbus}/bin/dbus-daemon"
          fi
        fi

        if ${isDarkNow}; then
        ${gtkModeSettings "$DRY_RUN_CMD $reassertBus" "prefer-dark" "Adwaita-dark"}
        else
        ${gtkModeSettings "$DRY_RUN_CMD $reassertBus" "prefer-light" "Adwaita"}
        fi
      '';
    };
  };
}
