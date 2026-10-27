# Light/dark switching for everything DMS does not theme itself: foot, tmux,
# and the dconf keys after an activation. See docs/theme.md.
{
  lib,
  pkgs,
  homeManagerConfig,
  homeDirectory,
  ...
}:
with lib;
let
  cfg = homeManagerConfig.theme or { enable = false; };
  isLinux = pkgs.stdenv.isLinux;
  homeDir = homeDirectory;

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

  # Custom tmux overlays, written for both palettes
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

  # The mode-dependent dconf keys DMS owns; nothing may declare them statically
  # (docs/theme.md, "The one rule"). The icon theme names must match
  # iconThemeLight/iconThemeDark in the dms module. `|| true`: activation runs
  # under `set -eu`, and a write that can't reach a bus must not fail it.
  gtkModeSettings = run: scheme: theme: icons: ''
    ${run} ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'${scheme}'" || true
    ${run} ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'${theme}'" || true
    ${run} ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/icon-theme "'${icons}'" || true
  '';

  # The current mode as a word in a file, written by the `theme-mode` template
  # on every transition. Readable without a session bus, which activation lacks
  # (`dms ipc` would fail there and read as light). Missing means dark.
  modeFile = "$HOME/.local/state/theme/mode";

  modeDark = pkgs.writeText "theme-mode-dark" "dark\n";
  modeLight = pkgs.writeText "theme-mode-light" "light\n";

  # Switches running foot instances (SIGUSR1 dark, SIGUSR2 light) and rewrites
  # the include new ones start from, atomically — see docs/theme.md, "foot and
  # tmux".
  footModeInclude = "$HOME/.config/foot/mode.ini";
  footSignal = pkgs.writeShellScript "theme-foot-signal" ''
    if [ "$(${pkgs.coreutils}/bin/cat "${modeFile}" 2>/dev/null)" = "light" ]; then
      mode=light
    else
      mode=dark
    fi

    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "${footModeInclude}")"
    ${pkgs.coreutils}/bin/printf '[main]\ninitial-color-theme=%s\n' "$mode" > "${footModeInclude}.new"
    ${pkgs.coreutils}/bin/mv -f "${footModeInclude}.new" "${footModeInclude}"

    if [ "$mode" = "light" ]; then
      ${pkgs.procps}/bin/pkill -x -USR2 foot || true
    else
      ${pkgs.procps}/bin/pkill -x -USR1 foot || true
    fi
  '';

  # tmux cannot be signalled: every running server re-sources the new file.
  tmuxReload = pkgs.writeShellScript "theme-tmux-reload" ''
    theme="$HOME/.local/state/tmux/current-theme.conf"
    [ -f "$theme" ] || exit 0
    ${pkgs.findutils}/bin/find /run/user/$(${pkgs.coreutils}/bin/id -u) /tmp -maxdepth 3 -name "default" -type s 2>/dev/null | while read -r sock; do
      ${pkgs.tmux}/bin/tmux -S "$sock" source-file "$theme" || true
    done
  '';
  isDarkNow = ''[ "$(${pkgs.coreutils}/bin/cat "${modeFile}" 2>/dev/null)" != "light" ]'';

in
{
  options.homeManagerConfig.theme = {
    enable = mkEnableOption "automatic dark/light mode toggling";
  };

  config = mkIf cfg.enable {
    home.packages = mkIf isLinux [
      (pkgs.writeShellScriptBin "theme-get" ''
        if ${isDarkNow}; then echo dark; else echo light; fi
      '')
      (pkgs.writeShellScriptBin "theme-toggle" ''
        exec dms ipc call theme toggle
      '')
    ];

    # Lets GTK3 read the theme keys from the portal (docs/theme.md,
    # "GTK_USE_PORTAL=1 is an improvement, not a prerequisite"). Takes effect
    # at the next login.
    xdg.configFile."uwsm/env" = mkIf isLinux {
      text = ''
        export GTK_USE_PORTAL=1
      '';
    };

    # Merged by DMS into every matugen run (runUserMatugenTemplates), so the
    # post_hooks fire on each transition. Only the mode moves; the colours are
    # Solarized, not matugen's. Both traps in this file — the bare header and
    # the required `input_path` — are in docs/theme.md.
    xdg.configFile."matugen/config.toml" = mkIf isLinux {
      text = ''
        [templates]

        [templates.theme-mode]
        input_path = "${modeDark}"
        input_path_modes = { dark = "${modeDark}", light = "${modeLight}" }
        output_path = "${homeDir}/.local/state/theme/mode"
        post_hook = "${footSignal}"

        [templates.tmux]
        input_path = "${solarizedDarkTheme}"
        input_path_modes = { dark = "${solarizedDarkTheme}", light = "${solarizedLightTheme}" }
        output_path = "${homeDir}/.local/state/tmux/current-theme.conf"
        post_hook = "${tmuxReload}"
      '';
    };

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

            # A real file, not a symlink, as on Linux.
            ${pkgs.coreutils}/bin/rm -f $HOME/.local/state/tmux/current-theme.conf
            ${pkgs.coreutils}/bin/install -m 0644 "$THEME" $HOME/.local/state/tmux/current-theme.conf

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

    # Seeds the file tmux sources at startup. A copy, not a symlink: matugen
    # later opens it with O_TRUNC, which would hit the read-only store.
    home.activation.initTmuxTheme = ''
      $DRY_RUN_CMD mkdir -p $HOME/.local/state/tmux
      if ${
        if isLinux then
          isDarkNow
        else
          ''[[ "$(/usr/bin/defaults read -g AppleInterfaceStyle 2>/dev/null)" == "Dark" ]]''
      }; then
        theme=${solarizedDarkTheme}
      else
        theme=${solarizedLightTheme}
      fi
      # Not behind $DRY_RUN_CMD: bash decides a word is an assignment before
      # expanding it, so `$DRY_RUN_CMD theme=...` would run it as a command.
      $DRY_RUN_CMD rm -f $HOME/.local/state/tmux/current-theme.conf
      $DRY_RUN_CMD install -m 0644 "$theme" $HOME/.local/state/tmux/current-theme.conf
    '';

    # foot.ini includes this, and a missing include stops foot starting.
    home.activation.initFootThemeInclude = mkIf isLinux ''
      $DRY_RUN_CMD mkdir -p $HOME/.config/foot
      if ${isDarkNow}; then
        mode=dark
      else
        mode=light
      fi
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/printf '[main]\ninitial-color-theme=%s\n' "$mode" \
        > $HOME/.config/foot/mode.ini
    '';

    # Puts the DMS-owned dconf keys back after home-manager's `dconf load` and
    # dconf-cleanup (docs/theme.md, "The activation guard"). Written out
    # longhand because these files are imported with the NixOS `lib`, which has
    # no `lib.hm.dag`.
    home.activation.reassertColorScheme = mkIf isLinux {
      after = [ "dconfSettings" ];
      before = [ ];
      data = ''
        # Prefer the live session bus so apps repaint now; fall back to a
        # throwaway one at boot, where only the database write matters.
        reassertBus=""
        if [ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
          if [ -S "/run/user/$(${pkgs.coreutils}/bin/id -u)/bus" ]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(${pkgs.coreutils}/bin/id -u)/bus"
          else
            reassertBus="${pkgs.dbus}/bin/dbus-run-session --dbus-daemon=${pkgs.dbus}/bin/dbus-daemon"
          fi
        fi

        if ${isDarkNow}; then
        ${gtkModeSettings "$DRY_RUN_CMD $reassertBus" "prefer-dark" "adw-gtk3-dark" "Papirus-Dark"}
        else
        ${gtkModeSettings "$DRY_RUN_CMD $reassertBus" "prefer-light" "adw-gtk3" "Papirus-Light"}
        fi
      '';
    };
  };
}
