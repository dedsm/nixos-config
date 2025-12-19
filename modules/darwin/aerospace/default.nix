{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.dedsm.aerospace;
in {
  options.dedsm.aerospace = {
    enable = mkEnableOption "Aerospace";
  };

  config = mkIf cfg.enable {
    services.aerospace = {
      enable = true;
      package = pkgs.unstable.aerospace;
      settings = {
        # 1. Keep Normalization Enabled (Recommended)
        enable-normalization-flatten-containers = true;
        enable-normalization-opposite-orientation-for-nested-containers = true;

        after-startup-command = [
        ];

        # 2. Focus Follows Mouse (Your requirement) & SketchyBar Integration
        on-focused-monitor-changed = ["move-mouse monitor-lazy-center"];
        on-focus-changed = ["move-mouse window-lazy-center"];

        exec-on-workspace-change = [
          "/bin/bash"
          "-c"
          "if command -v sketchybar >/dev/null; then sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE; fi"
        ];

        # 3. Gaps
        gaps = {
          inner.horizontal = 5;
          inner.vertical = 5;
          outer.left = 2;
          outer.bottom = 2;
          outer.top = 2;
          outer.right = 2;
        };

        # 4. Keybindings
        mode.main.binding = {
          # --- App Launching ---
          "cmd-alt-ctrl-shift-enter" = "exec-and-forget open -n -a Ghostty";

          # --- Media Control ---
          "cmd-alt-ctrl-x" = "exec-and-forget ${pkgs.nowplaying-cli}/bin/nowplaying-cli togglePlayPause";

          # --- Focus (Vim) ---
          "cmd-alt-ctrl-h" = "focus left";
          "cmd-alt-ctrl-j" = "focus down";
          "cmd-alt-ctrl-k" = "focus up";
          "cmd-alt-ctrl-l" = "focus right";

          "cmd-alt-ctrl-tab" = "focus dfs-next --boundaries-action wrap-around-the-workspace";

          # --- Movement (Throwing) ---
          "cmd-alt-ctrl-shift-h" = "move left";
          "cmd-alt-ctrl-shift-j" = "move down";
          "cmd-alt-ctrl-shift-k" = "move up";
          "cmd-alt-ctrl-shift-l" = "move right";

          # --- The "Join" Workflow (Replacing Split) ---
          "alt-shift-h" = "join-with left";
          "alt-shift-j" = "join-with down";
          "alt-shift-k" = "join-with up";
          "alt-shift-l" = "join-with right";

          # --- Resizing ---
          "alt-h" = "resize width -1";
          "alt-l" = "resize width +1";
          "alt-j" = "resize height -1";
          "alt-k" = "resize height -1";

          # --- Layouts ---
          "cmd-alt-ctrl-shift-space" = "layout floating tiling";
          "cmd-alt-ctrl-shift-q" = "layout tiles horizontal vertical";
          "cmd-alt-ctrl-shift-c" = "close --quit-if-last-window";
          "cmd-alt-ctrl-f" = "fullscreen --no-outer-gaps";

          # --- Multi-Monitor ---
          "cmd-alt-ctrl-1" = "summon-workspace 1";
          "cmd-alt-ctrl-2" = "summon-workspace 2";
          "cmd-alt-ctrl-3" = "summon-workspace 3";
          "cmd-alt-ctrl-4" = "summon-workspace 4";
          "cmd-alt-ctrl-5" = "summon-workspace 5";
          "cmd-alt-ctrl-6" = "summon-workspace 6";
          "cmd-alt-ctrl-7" = "summon-workspace 7";
          "cmd-alt-ctrl-8" = "summon-workspace 8";
          "cmd-alt-ctrl-9" = "summon-workspace 9";
          "cmd-alt-ctrl-shift-1" = "move-node-to-workspace 1";
          "cmd-alt-ctrl-shift-2" = "move-node-to-workspace 2";
          "cmd-alt-ctrl-shift-3" = "move-node-to-workspace 3";
          "cmd-alt-ctrl-shift-4" = "move-node-to-workspace 4";
          "cmd-alt-ctrl-shift-5" = "move-node-to-workspace 5";
          "cmd-alt-ctrl-shift-6" = "move-node-to-workspace 6";
          "cmd-alt-ctrl-shift-7" = "move-node-to-workspace 7";
          "cmd-alt-ctrl-shift-8" = "move-node-to-workspace 8";
          "cmd-alt-ctrl-shift-9" = "move-node-to-workspace 9";

           # --- App Launching (Hyprland Equivalents) ---
           "alt-shift-w" = "exec-and-forget open -a Firefox";
           "alt-shift-f" = "exec-and-forget open -a 'Google Chrome'";
           "alt-shift-s" = "exec-and-forget open -a Slack";
           "alt-shift-p" = "exec-and-forget open -a Finder";
           "alt-shift-c" = "exec-and-forget open -a Calculator";
           "cmd-alt-ctrl-p" = "exec-and-forget osascript -e 'tell application \"System Events\" to keystroke \" \" using {command down}'";

          # --- Monitor Focus & Movement ---
          "cmd-alt-ctrl-w" = "focus-monitor 1";
          "cmd-alt-ctrl-e" = "focus-monitor 2";
          "cmd-alt-ctrl-r" = "focus-monitor 3";
          "cmd-alt-ctrl-shift-w" = "move-node-to-monitor 1";
          "cmd-alt-ctrl-shift-e" = "move-node-to-monitor 2";
          "cmd-alt-ctrl-shift-r" = "move-node-to-monitor 3";
        };

        # workspace-to-monitor-force-assignment = {
        #   "1" = 1;
        #   "2" = 1;
        #   "3" = 1;
        #   "4" = 1;
        #   "5" = ["2" "3" "1"];
        #   "6" = ["2" "3" "1"];
        #   "7" = ["2" "3" "1"];
        #   "8" = ["3" "2" "1"];
        #   "9" = ["3" "2" "1"];
        # };
      };
    };
  };
}
