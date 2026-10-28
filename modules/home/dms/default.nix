{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  # Where the screenshot picker's three "Save" entries and every recording
  # write. Kept at ~/Downloads because that is where the hyprshot picker this
  # replaced put them.
  screenshotSaveDir = "${config.home.homeDirectory}/Downloads";

  # DMS 2.0 moved everything from `DankMaterialShell` to `dms`, leaving the old
  # names behind as compatibility symlinks; these are the real paths.
  configDir = "$HOME/.config/dms";
  stateDir = "$HOME/.local/state/dms";

  # The pickers on PATH (screenshot.nix, screencast.nix) and the declared
  # settings drop-in (settings.nix) live in their own files.
  screenshot = import ./screenshot.nix { inherit pkgs screenshotSaveDir; };
  screencast = import ./screencast.nix { inherit pkgs screenshotSaveDir; };
  declaredSettings = import ./settings.nix;

  # session.json is DMS's mutable runtime state — wallpaper, volumes, the
  # current mode — so it is deliberately not a store symlink. Two of its keys
  # are policy rather than state, though: the automatic light/dark schedule
  # that replaced darkman lives there, and its default is *off*. Seed those on
  # activation when they are absent, leaving everything else (and any later
  # change made from the UI) alone: `+` in jq lets the right-hand side win, so
  # existing values are never overwritten.
  sessionDefaults = pkgs.writeText "dms-session-defaults.json" (
    builtins.toJSON {
      themeModeAutoEnabled = true;
      # Sunrise/sunset from GeoClue2, the way darkman's usegeoclue worked.
      # "time" would switch on a fixed clock instead.
      themeModeAutoMode = "location";
      # Defaults to *true*, which makes the light/dark schedule share gamma
      # control's settings — and gamma control (night mode) is deliberately
      # manual here, so it has no schedule to share. The theme automation then
      # computes transitions from nothing: observed as a "next transition" ten
      # minutes out, dark in the middle of the afternoon, and light/dark
      # flapping within seconds.
      themeModeShareGammaSettings = false;
    }
  );

  # Recording turns do-not-disturb on so nothing pops up in the video; this
  # lets the recorder's own "Recording" and "Recording saved" notifications
  # through regardless. The saved one would otherwise land silently in history
  # whenever DND had been on before the recording started.
  #
  # Seeded into the writable settings.json rather than declared in the Nix-owned
  # drop-in (settings.nix), because `notificationRules` is also where the notification
  # context menu writes — permanent and timed (1h/4h) per-app mutes, and the
  # per-app "allow during DND" toggle. Declared here, the key would live in a
  # read-only file and every one of those would be lost at the next restart.
  screencastRule = pkgs.writeText "dms-screencast-rule.json" (
    builtins.toJSON {
      enabled = true;
      field = "appName";
      pattern = "Screencast";
      matchType = "exact";
      action = "default";
      urgency = "default";
      bypassDnd = true;
    }
  );

in
{
  options.dedsm.dms = {
    enable = lib.mkEnableOption "the DankMaterialShell user config";
  };

  config = lib.mkIf config.dedsm.dms.enable {
    home.activation.dmsSessionDefaults = ''
      state="${stateDir}/session.json"
      $DRY_RUN_CMD mkdir -p "$(dirname "$state")"
      if [ -f "$state" ]; then
        # Merge, existing values winning, via a temp file so a failed jq cannot
        # truncate live state.
        if ${pkgs.jq}/bin/jq -s '.[0] + .[1]' ${sessionDefaults} "$state" > "$state.new" 2>/dev/null; then
          $DRY_RUN_CMD mv -f "$state.new" "$state"
        else
          $DRY_RUN_CMD rm -f "$state.new"
        fi
      else
        $DRY_RUN_CMD install -m 0644 ${sessionDefaults} "$state"
      fi
    '';

    # Makes sure the Screencast rule is in the writable settings.json, leaving
    # every other rule — the ones the notification menu adds — alone. Ordered
    # after linkGeneration so that, on the switch from the old layout, it runs
    # once home-manager has removed the store symlink settings.json used to be.
    home.activation.dmsSettingsDefaults = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      settings="${configDir}/settings.json"
      $DRY_RUN_CMD mkdir -p "$(dirname "$settings")"
      # Only ever a leftover store symlink from before settings were split;
      # merging into it would copy every old declared key into the live file.
      if [ -L "$settings" ]; then
        $DRY_RUN_CMD rm -f "$settings"
      fi
      if [ -f "$settings" ]; then
        if ${pkgs.jq}/bin/jq --slurpfile rule ${screencastRule} '
            .notificationRules = ((.notificationRules // [])
              | if any(.[]; .field == $rule[0].field and .pattern == $rule[0].pattern)
                then . else . + $rule end)
          ' "$settings" > "$settings.new" 2>/dev/null; then
          $DRY_RUN_CMD mv -f "$settings.new" "$settings"
        else
          $DRY_RUN_CMD rm -f "$settings.new"
        fi
      else
        ${pkgs.jq}/bin/jq -n --slurpfile rule ${screencastRule} '{ notificationRules: $rule }' \
          > "$settings.new" && $DRY_RUN_CMD mv -f "$settings.new" "$settings"
      fi
    '';

    # On PATH for the CTRL+Print and CTRL+SHIFT+Print binds in the hyprland
    # module.
    home.packages = [
      screenshot
      screencast
    ];

    # DMS *does* watch its settings files (`watchChanges` on each FileView, plus
    # a FolderListModel on config.d), but neither fires for a rebuild:
    # home-manager re-links with `ln -Tsf`, replacing the symlink rather than the
    # file it points at, so the inode being watched — a store path — never
    # changes. Tested on 2.0.0 by re-linking this file exactly that way: the
    # running shell kept the old value. (An in-place edit of the real
    # settings.json, by contrast, is picked up live.) Hence the explicit restart,
    # which is safe now that nothing locks the screen on shell start (see
    # `lockAtStartup` in settings.nix).
    xdg.configFile."dms/config.d/10-nix.json".onChange = ''
      ${pkgs.systemd}/bin/systemctl --user try-restart dms.service || true
    '';
    xdg.configFile."dms/config.d/10-nix.json".text = builtins.toJSON declaredSettings;
  };
}
