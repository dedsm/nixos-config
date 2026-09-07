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
  # `run` is "$DRY_RUN_CMD …" from the activation script below, the only caller.
  # DMS writes these two keys itself on every theme build (adw-gtk3/adw-gtk3-dark,
  # not the Adwaita pair); this exists to put them back after an activation.
  # `|| true` matters on the activation path: home-manager activation runs under
  # `set -eu`, and a theme write that can't reach a bus must not fail the whole rebuild.
  gtkModeSettings = run: scheme: theme: ''
    ${run} ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'${scheme}'" || true
    ${run} ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'${theme}'" || true
  '';

  # The active mode, as a word in a file. Written by the matugen template below
  # on every theme change, which makes it readable without a session bus — the
  # activation scripts run from home-manager-<user>.service, which has none, and
  # `dms ipc` would fail there and silently read as light. Missing means "not
  # switched yet this install": treat that as dark, the default DMS starts in.
  modeFile = "$HOME/.local/state/theme/mode";

  # Template inputs for the mode marker. matugen picks one by the active
  # scheme (`input_path_modes`), so the file is always the mode it just built.
  modeDark = pkgs.writeText "theme-mode-dark" "dark\n";
  modeLight = pkgs.writeText "theme-mode-light" "light\n";

  # foot re-reads its config on SIGUSR1/SIGUSR2, which also select the
  # [colors-dark]/[colors-light] section (foot 1.27). Its colours are declared
  # in Nix rather than generated, so DMS's own foot template stays off and this
  # is the whole of the switch.
  #
  # Running instances are signalled; instances started *later* need the mode in
  # their config, because `initial-color-theme` only takes a literal `dark` or
  # `light` — foot has no "follow the system" value, and a foot launched while
  # the system is dark would otherwise paint light and be corrected by the zsh
  # hook a moment later. So the same hook writes the one-line include that
  # foot.ini pulls in (see the `defaults` module).
  #
  # Written via a temporary file and `mv`, which is atomic within $HOME: a foot
  # started mid-write must never see a truncated include, because a config file
  # it cannot parse is a *fatal* error (`foot --check-config` exits 230) rather
  # than a fallback to defaults.
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

  # tmux cannot be signalled: every running server has to be told to re-source
  # the file matugen just rewrote.
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
    # theme-get reads the marker file rather than asking DMS, so it also works
    # in a tty or before the shell is up (zsh calls it from every foot startup).
    home.packages = mkIf isLinux [
      (pkgs.writeShellScriptBin "theme-get" ''
        if ${isDarkNow}; then echo dark; else echo light; fi
      '')
      (pkgs.writeShellScriptBin "theme-toggle" ''
        exec dms ipc call theme toggle
      '')
    ];

    # DMS merges the [templates] section of this file into the matugen config it
    # generates (settings.runUserMatugenTemplates), so these render — and their
    # post_hooks run — on every theme change and every light/dark flip. That is
    # what replaced darkman's transition scripts.
    #
    # Neither template's colours come from matugen: this palette is Solarized,
    # declared above, and only the *mode* moves. `input_path_modes` picks the
    # file for the scheme matugen just built, which is why no hook has to work
    # out which mode it is in.
    #
    # `input_path` is repeated even though `input_path_modes` supersedes it:
    # matugen's Template struct declares it non-optional (src/template.rs), so
    # a template carrying only the modes fails to deserialise — and that is a
    # *config-level* failure, which silently takes every other template down
    # with it, DMS's own foot and GTK ones included.
    xdg.configFile."matugen/config.toml" = mkIf isLinux {
      text = ''
        # The bare table header below matters, and nothing above it may repeat
        # it. DMS merges this file by finding that header as a literal
        # substring and copying from there to the end of the file
        # (extractTOMLSection, core/internal/matugen/matugen.go): a dotted
        # sub-table header does not match it, so without a bare one the whole
        # section is silently dropped — matugen still reports success, having
        # rendered only DMS's own templates. Equally, writing the header text
        # in a comment first makes the copy start mid-comment and matugen fails
        # to parse its own config.
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

    # Neovim needs nothing here: its TUI queries the terminal background (OSC 11)
    # at startup and sets 'background' itself, so it follows foot.

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

            # A real file, not a symlink: the same path is matugen's output on
            # Linux, and keeping both platforms identical avoids surprises.
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

    # Seeds the file tmux sources at startup, for servers started before the
    # first theme flip of the boot. Copied rather than symlinked on purpose:
    # matugen owns this path afterwards and opens it with O_TRUNC, which
    # follows a symlink straight into the read-only store and fails.
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
      # expanding it, so `$DRY_RUN_CMD theme=...` runs the assignment as a
      # command name once DRY_RUN_CMD is empty.
      $DRY_RUN_CMD rm -f $HOME/.local/state/tmux/current-theme.conf
      $DRY_RUN_CMD install -m 0644 "$theme" $HOME/.local/state/tmux/current-theme.conf
    '';

    # foot.ini `include`s this, and a missing include stops foot starting at
    # all, so it is seeded here as well as written by the theme hook — the
    # generated file has to exist from the first activation, before any theme
    # change has happened.
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

    # home-manager's `dconf load` runs on every activation, and its dconf-cleanup pass
    # resets keys that a generation stopped managing back to their (light) schema
    # defaults. Either one bumps the dconf shm invalidation flag, so live apps re-read
    # the light value the next time they repaint — which is why a mid-afternoon rebuild
    # used to knock Firefox/Slack back to light minutes after darkman had switched them.
    # Re-assert the mode DMS actually wants, ordered after home-manager's own write.
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
        ${gtkModeSettings "$DRY_RUN_CMD $reassertBus" "prefer-dark" "adw-gtk3-dark"}
        else
        ${gtkModeSettings "$DRY_RUN_CMD $reassertBus" "prefer-light" "adw-gtk3"}
        fi
      '';
    };
  };
}
