{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
let
  tomlFormat = pkgs.formats.toml { };

  herdrPkg = pkgs.unstable.herdr;

  # Every herdr command this module runs is best-effort: a rebuild must not
  # fail because the multiplexer is unreachable. But it must not be *silent*
  # either, which is what a bare `|| true` bought. This wrapper runs one
  # command, passes its stdout through, always exits 0, and turns a failure
  # into a warning on stderr.
  #
  # The case worth surfacing is `protocol_mismatch`. herdr's CLI talks to a
  # running server over `herdr.sock` whenever there is one, and refuses when
  # its protocol is newer than the server's — exactly what a rebuild that
  # bumps the package produces, because the session that rebuild was started
  # from is still running the old binary. Every socket command then fails
  # until that server is restarted, so the plugin registry and the config
  # reload silently did nothing.
  #
  # It also blocked the whole activation: `plugin link` was guarded with
  # `|| true`, but the `plugin list | jq | while` pipeline below was not, and
  # under the activation script's `set -o pipefail` a failing `list` took
  # home-manager-<user>.service down with it (exit 1, "Failed to start Home
  # Manager environment").
  #
  # `server_not_running` stays quiet: `unlink` and `reload-config` only work
  # through the socket and there is usually no server up during activation,
  # which is the normal case rather than a problem. `link` and `list` fall
  # back to editing plugins.json directly and succeed either way.
  herdrTry = pkgs.writeShellScript "herdr-try" ''
    # fd 3 is the real stdout, so the command's own output still reaches the
    # caller — `plugin list --json` is piped into jq — while stderr, where
    # herdr writes its JSON errors, is captured for the warning.
    exec 3>&1

    herdrStatus=0
    herdrError=$(${lib.getExe herdrPkg} "$@" 2>&1 1>&3 3>&-) || herdrStatus=$?

    if [ "$herdrStatus" -eq 0 ]; then
      exit 0
    fi

    case $herdrError in
      *server_not_running*) exit 0 ;;
    esac

    # herdr reports a failure as a single JSON line. Unwrap the human message
    # — for `protocol_mismatch` it is several lines and names the fix — and
    # fall back to the raw output for anything that is not that shape.
    herdrMessage=$(printf '%s\n' "$herdrError" | ${lib.getExe pkgs.jq} -r '.error.message // empty' 2>/dev/null)
    [ -n "$herdrMessage" ] || herdrMessage=''${herdrError:-(no output)}

    echo "warning: herdr $* failed (exit $herdrStatus)" >&2
    echo "$herdrMessage" >&2

    case $herdrError in
      *protocol_mismatch*)
        echo "This generation's herdr config and plugins were not applied to the running server; they take effect when it restarts." >&2
        ;;
    esac

    exit 0
  '';

  navPkg = pkgs.local.vim-herdr-navigation;
  navRoot = "${navPkg}/share/vim-herdr-navigation";

  # Registered with `herdr plugin link` at activation, and pruned from the
  # registry when dropped from this list. See "Plugins" in docs/herdr.md.
  plugins = [
    {
      id = "vim-herdr-navigation";
      root = navRoot;
    }
  ];

  # `ctrl+h/j/k/l` go through the navigation plugin rather than binding
  # `focus_pane_*` directly, which is what makes them vim-aware: the action
  # forwards the key into the pane when it is running Vim/Neovim and moves
  # herdr's focus otherwise. herdr rejects a key that is bound twice, so the
  # `focus_pane_*` actions keep only their `prefix+` defaults.
  navKeybinds =
    map
      (d: {
        key = "ctrl+${d.key}";
        type = "plugin_action";
        command = "vim-herdr-navigation.${d.dir}";
        description = "Navigate ${d.dir} (vim/herdr)";
      })
      [
        {
          key = "h";
          dir = "left";
        }
        {
          key = "j";
          dir = "down";
        }
        {
          key = "k";
          dir = "up";
        }
        {
          key = "l";
          dir = "right";
        }
      ];

  settings = {
    # The first-run notification setup. herdr shows it whenever this key is
    # missing, then persists `onboarding = false` back into config.toml once
    # dismissed — a write that fails against a store symlink ("Read-only file
    # system"), so the welcome screen came back on every launch. Declaring the
    # post-onboarding value here is the fix; the notification preferences that
    # modal asks about are set under `ui` below.
    onboarding = false;

    keys = {
      # Same prefix as tmux, so the muscle memory carries over while both
      # multiplexers are installed side by side.
      prefix = "ctrl+f";

      # Prefix-free pane movement on the same chords `vim-tmux-navigator`
      # already owns under tmux, via the plugin actions defined above.
      #
      # `ctrl+alt+h/j/k/l` is herdr's own suggestion and is not used: `CTRL +
      # ALT + L` is the hyprlock bind on manwe, and diverging per host is worse
      # than picking a chord that is free on both.
      command = navKeybinds;

      # tmux muscle memory, kept as aliases beside the herdr defaults. herdr
      # names a split after the divider it draws, so "vertical" is the
      # side-by-side one that tmux calls `split-window -h`.
      split_vertical = [
        "prefix+v"
        "prefix+|"
      ];
      split_horizontal = [
        "prefix+minus"
        "prefix+\\"
      ];

      # Jump straight to a worktree. Ships unset; only 1..9 are reachable, so
      # `goto` (prefix+g) stays the answer past the ninth workspace.
      switch_workspace = "prefix+shift+1..9";

      # Agent navigation. All three ship unset upstream; without them the
      # sidebar is read-only and reaching an agent means jumping to its
      # workspace. `prefix+1..9` is switch_tab and `prefix+shift+1..9` is
      # switch_workspace above, so ctrl is the free modifier for the indexed
      # jump — see "Agent navigation" in docs/herdr.md for the caveat, and
      # `ui.agent_panel_sort` below for what next/previous_agent walks.
      focus_agent = "prefix+ctrl+1..9";
      next_agent = "prefix+a";
      previous_agent = "prefix+shift+a";
    };

    ui = {
      # Mouse at the multiplexer level: click to focus a pane, drag a border to
      # resize, wheel-scroll the scrollback. herdr still forwards events to an
      # inner TUI that asks for mouse reporting, so this costs the terminal's
      # own click-drag selection (hold shift for that) rather than app input.
      #
      # There is no runtime toggle to fall back on — herdr 0.7.5 has no
      # `:set mouse` equivalent, and nothing mouse-related in its bindable
      # action list — so this key is the only switch.
      mouse_capture = true;

      # herdr owns agent notifications, for every recognised agent rather than
      # just Claude Code — whose own notification hooks are disabled in the
      # claude-code module so the same prompt does not notify twice. See
      # "Notifications" in docs/herdr.md.
      #
      # "system" hands off to the OS notification service: `notify-send` (hence
      # libnotify below) into swaync on Linux, `osascript`/`display
      # notification` into Notification Center on Darwin. The alternatives are
      # "herdr" (in-app toasts, invisible while detached) and "terminal" (OSC
      # 9/777, dependent on the outer terminal).
      toast.delivery = "system";

      # Agent state changes in *background* workspaces. Unchanged herdr default,
      # pinned because the skipped onboarding modal would have asked.
      sound.enabled = true;

      # Order the agent panel as an attention queue rather than grouping by
      # workspace (upstream's "spaces" default). That is what makes
      # `next_agent` mean "next agent waiting on me" — and it is the only
      # answer past nine agents, since `focus_agent` stops at 9 and herdr has
      # no agent equivalent of the `goto` workspace picker.
      agent_panel_sort = "priority";

      sidebar = {
        # Worktree-oriented layout: bare repos with many `work/<branch>`
        # checkouts, so branch and dirty state matter more than the pane title.
        spaces.rows = [
          [
            "state_icon"
            "workspace"
          ]
          [
            "branch"
            "git_status"
          ]
        ];

        # Claude Code writes its current activity to the terminal title, which
        # turns that row into a live "what is this agent doing" column. The
        # override key must be herdr's canonical agent id.
        agents.rows_by_agent.claude = [
          [
            "state_icon"
            "agent"
            "state_text"
          ]
          [ "terminal_title_stripped" ]
          [
            "workspace"
            "tab"
          ]
        ];
      };
    };

    session = {
      # A reboot kills the pane processes either way; this lets supported agents
      # reopen their own conversation rather than coming back as a bare shell.
      resume_agents_on_restore = true;
    };

    theme = {
      # herdr detects the host terminal's light/dark appearance itself, so it
      # needs none of the darkman/dark-notify bridge the `theme` module builds
      # for tmux. Upstream defaults this to false.
      auto_switch = true;
      dark_name = "solarized";
      light_name = "solarized-light";

      # Fallback when appearance detection fails; without it that case lands on
      # herdr's catppuccin default.
      name = "solarized";
    };
  };
in
with lib;
mkIf (homeManagerConfig.herdr.enable or false) {
  # `ui.toast.delivery = "system"` shells out to `notify-send` by name on
  # Linux, so libnotify has to be on PATH. Darwin needs nothing extra —
  # herdr goes through osascript there.
  home.packages = [ herdrPkg ] ++ optional pkgs.stdenv.isLinux pkgs.libnotify;

  # Single-file link on purpose: `~/.config/herdr/` stays a real directory so
  # herdr can still write its logs and session state next to the config.
  xdg.configFile."herdr/config.toml" = {
    source = tomlFormat.generate "herdr-config.toml" settings;

    # Apply on rebuild instead of waiting for the next launch. Copied from
    # the `programs.herdr` module on home-manager master, which this module
    # replaces until that lands in a release — see docs/herdr.md. That one
    # writes `|| true` for the (expected) case of no server running during
    # activation; `herdrTry` keeps that quiet while still reporting a
    # server that refused the reload.
    onChange = "${herdrTry} server reload-config";
  };

  # The editor half of the navigation plugin: `<C-h/j/k/l>` move between
  # Neovim splits and cross into the neighbouring herdr pane at an edge. It
  # lives in `after/plugin` so it wins over the `vim-tmux-navigator`
  # mappings, and falls back to them when $HERDR_PANE_ID is unset, i.e. under
  # tmux. The nvim module links `config/` recursively and has no `after/`,
  # so this is the only thing there.
  xdg.configFile."nvim/after/plugin/herdr-nav.lua" = mkIf (homeManagerConfig.nvim.enable or false) {
    source = "${navRoot}/editor/nvim.lua";
  };

  # `plugins.json` is deliberately *not* a store symlink: herdr rewrites it
  # on every link/unlink/enable/disable, so managing it declaratively would
  # reproduce the read-only failure the `onboarding` setting used to hit.
  # `herdr plugin link` needs no running server, is idempotent, and replaces
  # the entry for an id when its path changes — which it does on every
  # rebuild that bumps a plugin's store path.
  home.activation.herdrPlugins = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      herdrPluginIds="${concatMapStringsSep " " (p: p.id) plugins}"

      ${concatMapStringsSep "\n" (p: ''
        $DRY_RUN_CMD ${herdrTry} plugin link ${p.root} >/dev/null
      '') plugins}

      # Drop store-linked plugins that are no longer declared here. Anything
      # linked by hand from outside the store is left alone on purpose.
      #
      # `link` and `list` fall back to editing plugins.json directly, but
      # `unlink` always goes through herdr.sock — with no server up it fails
      # with `server_not_running`. So this half is best-effort: a plugin
      # removed from the list above may linger in the registry until the
      # next activation that happens while herdr is running.
      #
      # Everything here goes through `herdrTry`, which always exits 0 — a
      # failing `list` would otherwise fail the pipeline (`set -o pipefail`)
      # and abort the activation. jq handles its empty output as no plugins.
      ${herdrTry} plugin list --json \
        | ${getExe pkgs.jq} -r '.result.plugins[]? | select(.plugin_root | startswith("/nix/store")) | .plugin_id' \
        | while read -r id; do
            case " $herdrPluginIds " in
              *" $id "*) ;;
              *) $DRY_RUN_CMD ${herdrTry} plugin unlink "$id" >/dev/null ;;
            esac
          done
    '';
  };
}
