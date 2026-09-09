attrs@{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
with lib;
let
  # Solarized Osaka Night, vendored from the official theme registry
  # (AvengeMedia/dms-plugin-registry, themes/solarized-osaka-night, by
  # setiapam, MIT). Solarized's accents — #29a298 cyan, #268bd3 blue, #b28500
  # yellow, #db302d red — over near-black surfaces in dark mode and Solarized's
  # own base3/base2 in light. Vendored rather than installed through the
  # registry browser so the palette is pinned and reproducible.
  theme = ./solarized-osaka-night.json;

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
in
mkIf (homeManagerConfig.dms.enable or false) {
  home.activation.dmsSessionDefaults = ''
    state="$HOME/.local/state/DankMaterialShell/session.json"
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

  # DMS writes settings.json itself on every UI toggle, so home-manager's
  # store symlink makes it read-only. That is a supported mode: the shell
  # detects it, keeps the change live for the session, and the settings modal
  # offers a "copy settings.json" button that puts the full JSON on the
  # clipboard to be folded back in here.
  #
  # Mostly only what differs from upstream's defaults is declared — the file has
  # ~540 keys and listing the ones that already agree would bury the ones that
  # matter. The exceptions are pinned on purpose: `lockAtStartup`,
  # `lockPamExternallyManaged`, `lockPamInlineFprint`, `runUserMatugenTemplates`
  # and the two suspend timeouts currently *equal* upstream's default, and are
  # stated anyway because each one is load-bearing for the login flow or the
  # theme chain and a default flip upstream would be silent.
  # DMS *does* watch this file (`watchChanges` on its FileView), but the watch
  # never fires for a rebuild: home-manager replaces the symlink rather than the
  # file it points at, so the inode being watched — a store path — never
  # changes. Hence the explicit restart, which is safe now that nothing locks
  # the screen on shell start (see `lockAtStartup` below).
  xdg.configFile."DankMaterialShell/settings.json".onChange = ''
    ${pkgs.systemd}/bin/systemctl --user try-restart dms.service || true
  '';

  xdg.configFile."DankMaterialShell/settings.json".text = builtins.toJSON {
    # --- theme
    currentThemeName = "custom";
    currentThemeCategory = "custom";
    customThemeFile = toString theme;
    # The Solarized palette this repo uses everywhere else is declared in the
    # `theme` module and reaches foot/tmux through matugen's user templates;
    # this keeps those templates running.
    runUserMatugenTemplates = true;

    # --- lock screen authentication
    #
    # Point the password stack at /etc/pam.d/dankshell (declared by
    # modules/nixos/dms), which is what carries the gnome-keyring unlock and
    # the pam_exec stamp dedsm.fingerprintPolicy needs. Fingerprint stays in
    # the declared /etc/pam.d/dankshell stack, because externally-managed mode
    # suppresses DMS's own parallel context; it still goes through fprintd, so
    # the policy governs it. maxFprintTries mirrors the policy's failureLimit
    # so the UI stops retrying at the same point the gate stops allowing.
    # Deliberately false, which reads backwards: "externally managed" makes DMS
    # authenticate against /etc/pam.d/**login** (Modules/Lock/Pam.qml), and this
    # host keeps that stack password-only for tty logins. Left off, DMS takes
    # the next branch — /etc/pam.d/dankshell, because the file exists — which is
    # the stack modules/nixos/dms declares. It also stops DMS suppressing its
    # own fingerprint context, so the sensor and the password field stay live at
    # the same time instead of the sensor blocking the stack.
    #
    # DMS still writes an unused user-level PAM file under ~/.local/state; the
    # /etc one wins.
    lockPamExternallyManaged = false;
    lockPamInlineFprint = false;
    # Name the stack outright rather than leaving the UI on "Auto", which
    # resolves by falling through a chain — custom path, then /etc/pam.d/login
    # if externally managed, then /etc/pam.d/dankshell *if that file happens to
    # exist*, then a generated user-level one. Pinning it means the lock screen
    # cannot quietly authenticate against a different stack than the one this
    # repo declares.
    lockPamPath = "/etc/pam.d/dankshell";
    enableFprint = true;
    maxFprintTries = 5;

    # --- idle and lock, replacing hypridle's listeners
    # 5 minutes to lock, 10 to blank, on both AC and battery — the timings
    # hypridle used. Suspend stays with logind (see docs/hibernation.md).
    acLockTimeout = 300;
    acMonitorTimeout = 600;
    acSuspendTimeout = 0;
    batteryLockTimeout = 300;
    batteryMonitorTimeout = 600;
    batterySuspendTimeout = 0;
    lockBeforeSuspend = true;
    # Nothing to lock at startup: greetd's greeter has already authenticated
    # before the session exists. It would also be actively wrong here — the
    # setting fires from Lock.qml's Component.onCompleted, i.e. on every *shell*
    # start, including the restart `systemd.restartIfChanged` performs during a
    # `nixos-rebuild switch`.
    lockAtStartup = false;

    # --- location
    # The light/dark schedule follows sunrise/sunset through GeoClue2, which
    # DMS prefers over IP geolocation when it is allowed to use it
    # (services.geoclue2.appConfig.dms in modules/nixos/dms).
    useAutoLocation = true;

    # --- bar
    # The workspace pills show their Hyprland number, the way waybar's
    # `{name}` did.
    showWorkspaceIndex = true;
    # waybar's `idle_inhibitor`, in two halves. The setting only lights an
    # indicator on the bar while inhibition is *already* active
    # (ControlCenterButton.qml checks `SessionService.idleInhibited`), so the
    # thing you actually press is the "Keep Awake" tile — which has to be listed
    # here, because declaring this key means owning the whole tile list. The
    # rest of the list is DMS's default order.
    controlCenterShowIdleInhibitorIcon = true;
    controlCenterWidgets =
      map
        (id: {
          inherit id;
          enabled = true;
          width = 50;
        })
        [
          "volumeSlider"
          "brightnessSlider"
          "wifi"
          "bluetooth"
          "audioOutput"
          "audioInput"
          "nightMode"
          "darkMode"
          "idleInhibitor"
        ];

    # Workspace pills also carry the icons of the windows on each workspace, with
    # the focused window's icon highlighted.
    showWorkspaceApps = true;
    workspaceActiveAppHighlightEnabled = true;
    # No drop shadow under the bar.
    barElevationEnabled = false;
    # Bar geometry. Declaring `barConfigs` means owning the whole ~55-key bar
    # object, so everything below except spacing/innerPadding/barInsetPadding is
    # upstream's default verbatim. Do not paste `dms ipc settings dump` in here to
    # refresh it: the bar settings tab rebuilds the entry from only the fields it
    # edits, so a value that has been touched in the UI comes back with keys
    # missing, and the missing ones would then read as their *property* defaults.
    barConfigs = [
      {
        id = "default";
        name = "Main Bar";
        enabled = true;
        position = 0;
        screenPreferences = [ "all" ];
        showOnLastDisplay = true;
        leftWidgets = [
          "launcherButton"
          "workspaceSwitcher"
          "focusedWindow"
        ];
        centerWidgets = [
          "music"
          "clock"
          "weather"
        ];
        rightWidgets = [
          "systemTray"
          "clipboard"
          "cpuUsage"
          "memUsage"
          "notificationButton"
          "battery"
          "controlCenterButton"
        ];
        spacing = 0;
        innerPadding = (-2);
        barInsetPadding = 4;
        bottomGap = 0;
        transparency = 1.0;
        widgetTransparency = 1.0;
        squareCorners = false;
        noBackground = false;
        maximizeWidgetIcons = false;
        maximizeWidgetText = false;
        removeWidgetPadding = false;
        widgetPadding = 8;
        gothCornersEnabled = false;
        gothCornerRadiusOverride = false;
        gothCornerRadiusValue = 12;
        borderEnabled = false;
        borderColor = "surfaceText";
        borderOpacity = 1.0;
        borderThickness = 1;
        widgetOutlineEnabled = false;
        widgetOutlineColor = "primary";
        widgetOutlineOpacity = 1.0;
        widgetOutlineThickness = 1;
        fontScale = 1.0;
        iconScale = 1.0;
        autoHide = false;
        autoHideStrict = false;
        autoHideDelay = 250;
        showOnWindowsOpen = false;
        openOnOverview = false;
        visible = true;
        popupGapsAuto = true;
        popupGapsManual = 4;
        maximizeDetection = true;
        useOverlayLayer = false;
        scrollEnabled = true;
        scrollXBehavior = "column";
        scrollYBehavior = "workspace";
        shadowIntensity = 0;
        shadowOpacity = 60;
        shadowColorMode = "default";
        shadowCustomColor = "#000000";
        clickThrough = false;
        hoverPopouts = false;
        hoverPopoutDelay = 150;
      }
    ];

    # --- date formats
    # Both default to "", which falls back to the locale's short forms.
    clockDateFormat = "ddd d MMM yyyy";
    lockDateFormat = "dddd, MMMM d";

    # --- carried over from the trial
    cornerRadius = 12;
    controlCenterShowMicPercent = true;
    osdPowerProfileEnabled = true;
  };
}
