# The declared half of DMS's settings, as a `config.d` drop-in.
#
# DMS 2.0 loads settings.json and then every `config.d/*.json` over it in
# lexicographic order, later files winning, and saves a GUI change to
# whichever file the key came from. So the keys below live in a store symlink
# DMS cannot write, while settings.json itself is an ordinary file: a GUI
# change to any key declared here is live for the session only (and the shell
# logs a failed write), but a change to anything *else* persists. Before 2.0
# the whole settings.json was the store symlink, and every GUI change was lost.
#
# Only what differs from upstream's defaults is declared — listing the ~540
# keys that already agree would bury the ones that matter. The exceptions are
# pinned on purpose: `lockAtStartup`, `lockPamExternallyManaged`,
# `lockPamInlineFprint`, `runUserMatugenTemplates` and the two suspend
# timeouts currently *equal* upstream's default, and are stated anyway because
# each one is load-bearing for the login flow or the theme chain and a default
# flip upstream would be silent.
#
# Written in the current schema (`configVersion` below). A file older than the
# shell is migrated on every load, and the migration's result then fails to
# save — which is what this file did for the whole of 2.0.0 until it was
# rewritten. When upstream bumps the version, regenerate the affected keys from
# `dms ipc call settings dump` (barConfigs excepted, see there).
let
  # Solarized Osaka Night, vendored from the official theme registry
  # (AvengeMedia/dms-plugin-registry, themes/solarized-osaka-night, by
  # setiapam, MIT). Solarized's accents — #29a298 cyan, #268bd3 blue, #b28500
  # yellow, #db302d red — over near-black surfaces in dark mode and Solarized's
  # own base3/base2 in light. Vendored rather than installed through the
  # registry browser so the palette is pinned and reproducible.
  theme = ./solarized-osaka-night.json;
in
{
  configVersion = 42;

  # --- theme
  currentThemeName = "custom";
  currentThemeCategory = "custom";
  # Interpolated, not `toString`. `toString ./file` yields the path *inside the
  # flake source* ("/nix/store/<hash>-source/modules/.../solarized-osaka-night.json")
  # as a plain string, which adds no store reference: the scanner only registers
  # hashes belonging to the derivation's inputs, and the source tree is not one of
  # this file's. The rendered settings had zero references (`nix-store -q
  # --references` on it printed nothing), so the next garbage collection deleted
  # the `-source` path out from under a live config and left a dangling pointer.
  # DMS then logs `Theme data not available for: custom` and its whole theme
  # build stops — no dconf write, no matugen run, so the mode marker, foot and
  # tmux all freeze at whatever the last successful transition wrote.
  # Interpolating copies the JSON in as a store path of its own and registers it,
  # which is what makes GC respect it.
  customThemeFile = "${theme}";
  # The Solarized palette this repo uses everywhere else is declared in the
  # `theme` module and reaches foot/tmux through matugen's user templates;
  # this keeps those templates running.
  runUserMatugenTemplates = true;
  # Papirus' tray icons are one flat colour per variant, so each mode needs
  # its own (docs/theme.md, "The icon theme is a third DMS-owned key"). The
  # theme module's activation guard writes the same two names.
  iconThemePerMode = true;
  iconThemeLight = "Papirus-Light";
  iconThemeDark = "Papirus-Dark";
  # `cornerRadius = 12` before 2.0; the schema migration maps that radius onto
  # the new strength scale as 38.
  radiusStrength = 38;

  # --- lock screen authentication
  #
  # Point the password stack at /etc/pam.d/dankshell (declared by
  # modules/nixos/dms), which is what carries the gnome-keyring unlock and
  # the pam_exec stamp dedsm.fingerprintPolicy needs. maxFprintTries mirrors
  # the policy's failureLimit so the UI stops retrying at the same point the
  # gate stops allowing.
  #
  # Deliberately false, which reads backwards: "externally managed" makes DMS
  # authenticate against /etc/pam.d/**login** (Modules/Lock/Pam.qml), and this
  # host keeps that stack password-only for tty logins. It would also suppress
  # DMS's own parallel fingerprint context, so the sensor and the password
  # field stay live at the same time only with it off.
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

  # --- wellbeing
  # Digital Wellbeing (new in 2.0, on by default) records how long each app
  # holds focus, for screen-time limits. Not wanted here.
  wellbeingEnabled = false;

  # --- bar
  # No drop shadow under the bar.
  barElevationEnabled = false;
  # Declaring `barConfigs` means owning the whole bar object, so everything
  # below except spacing/innerPadding/barInsetPadding and the two widget
  # entries is upstream's default verbatim (Common/settings/SettingsSpec.js).
  # Do not paste `dms ipc call settings dump` in here to refresh it: the bar
  # settings tab rebuilds the entry from only the fields it edits, so a value
  # that has been touched in the UI comes back with keys missing, and the
  # missing ones would then read as their *property* defaults.
  barConfigs = [
    {
      id = "default";
      name = "Main Bar";
      enabled = true;
      position = 0;
      screenPreferences = [ "all" ];
      showOnLastDisplay = true;
      # Widget options are per widget instance since 2.0 (they were global
      # keys before), so a widget with any set becomes an object.
      leftWidgets = [
        "launcherButton"
        {
          id = "workspaceSwitcher";
          enabled = true;
          # The workspace pills show their Hyprland number, the way waybar's
          # `{name}` did, and carry the icons of the windows on each
          # workspace, the focused one highlighted.
          showWorkspaceIndex = true;
          showWorkspaceApps = true;
          workspaceActiveAppHighlightEnabled = true;
        }
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
        {
          id = "controlCenterButton";
          enabled = true;
          showMicPercent = true;
          # waybar's `idle_inhibitor`, in two halves: this only lights an
          # indicator while inhibition is *already* active, and the thing you
          # actually press is the control centre's "Keep Awake" tile
          # (`idleInhibitor`), in upstream's default tile list since 2.0.
          showIdleInhibitorIcon = true;
        }
      ];
      spacing = 0;
      innerPadding = (-2);
      barInsetPadding = 4;
      barLengthPadding = 0;
      barLengthMode = "full";
      barLengthPercent = 80;
      bottomGap = 0;
      attachToScreenEdge = false;
      followInterfaceStyle = true;
      transparency = 1.0;
      surfaceColor = "default";
      surfaceCustomColor = "#6750A4";
      widgetFollowInterfaceStyle = true;
      widgetTransparency = 1.0;
      squareCorners = false;
      noBackground = false;
      widgetStyle = "pills";
      maximizeWidgetIcons = false;
      maximizeWidgetText = false;
      widgetPadding = 8;
      batteryColorMode = "theme";
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
      scrollXBehavior = "focusWindow";
      scrollYBehavior = "workspace";
      middleClickAction = "none";
      rightClickAction = "none";
      clickActionFollowMouse = false;
      shadowIntensity = 0;
      shadowOpacity = 60;
      shadowColorMode = "default";
      shadowCustomColor = "#000000";
      shadowDirectionMode = "inherit";
      shadowDirection = "top";
      clickThrough = false;
      hoverPopouts = false;
      hoverPopoutDelay = 150;
    }
  ];

  # --- clock and date formats
  # Seconds in the bar clock (and, through the same shared format, in the
  # lock screen's and the greeter's). Defaults to false. It also raises the
  # bar's SystemClock precision from Minutes to Seconds, so the clock widget
  # repaints once a second instead of once a minute.
  showSeconds = true;
  # Both default to "", which falls back to the locale's short forms.
  clockDateFormat = "ddd d MMM yyyy";
  lockDateFormat = "dddd, MMMM d";

  # --- carried over from the trial
  osdPowerProfileEnabled = true;
}
