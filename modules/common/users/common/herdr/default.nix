{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}: let
  tomlFormat = pkgs.formats.toml {};

  settings = {
    keys = {
      # Same prefix as tmux, so the muscle memory carries over while both
      # multiplexers are installed side by side.
      #
      # Deliberately no prefix-free `ctrl+alt+h/j/k/l` chords: `CTRL + ALT + L`
      # is already the hyprlock bind on manwe, and a binding set that differs
      # per host is worse than one extra keypress on both.
      prefix = "ctrl+f";

      # tmux muscle memory, kept as aliases beside the herdr defaults. herdr
      # names a split after the divider it draws, so "vertical" is the
      # side-by-side one that tmux calls `split-window -h`.
      split_vertical = ["prefix+v" "prefix+|"];
      split_horizontal = ["prefix+minus" "prefix+\\"];

      # Jump straight to a worktree. Ships unset; only 1..9 are reachable, so
      # `goto` (prefix+g) stays the answer past the ninth workspace.
      switch_workspace = "prefix+shift+1..9";
    };

    ui = {
      # Keyboard-only workflow (`vim.opt.mouse = ""` in the nvim config says the
      # same thing). Leaving capture off also hands mouse events to whatever TUI
      # is running inside the pane rather than eating them at the multiplexer.
      mouse_capture = false;

      sidebar = {
        # Worktree-oriented layout: bare repos with many `work/<branch>`
        # checkouts, so branch and dirty state matter more than the pane title.
        spaces.rows = [
          ["state_icon" "workspace"]
          ["branch" "git_status"]
        ];

        # Claude Code writes its current activity to the terminal title, which
        # turns that row into a live "what is this agent doing" column. The
        # override key must be herdr's canonical agent id.
        agents.rows_by_agent.claude = [
          ["state_icon" "agent" "state_text"]
          ["terminal_title_stripped"]
          ["workspace" "tab"]
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
      home.packages = [pkgs.unstable.herdr];

      # Single-file link on purpose: `~/.config/herdr/` stays a real directory so
      # herdr can still write its logs and session state next to the config.
      xdg.configFile."herdr/config.toml".source =
        tomlFormat.generate "herdr-config.toml" settings;
    }
