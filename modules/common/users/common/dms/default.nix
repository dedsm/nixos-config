attrs@{
  lib,
  homeDirectory,
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

  # Where the screenshot picker's three "Save" entries and every recording
  # write. Kept at ~/Downloads because that is where the hyprshot picker this
  # replaced put them.
  screenshotSaveDir = "${homeDirectory}/Downloads";

  # DMS 2.0 moved everything from `DankMaterialShell` to `dms`, leaving the old
  # names behind as compatibility symlinks; these are the real paths.
  configDir = "$HOME/.config/dms";
  stateDir = "$HOME/.local/state/dms";

  # The screenshot picker (CTRL+Print in the hyprland module): `menu` shows six
  # entries — region, window and monitor, each as copy and save — through
  # `dms dmenu`, which reads them from stdin and prints the chosen one. The
  # other form, `dms-screenshot <target> <copy|save>`, captures directly.
  #
  # `dms dmenu` is new in 2.0. Before it the launcher had no stdin mode at all,
  # so this list was a launcher *plugin* — with a plugin_settings.json seed to
  # enable it, and a QML disk-cache purge on every change, because Qt validates
  # that cache by mtime and every store file has the same one.
  #
  # Window and monitor are *pickers*, as `hyprshot -m window` and `-m output`
  # were. DMS has no picker of its own — `screenshot window` only ever takes the
  # active window and the region selector snaps only to DMS's own popouts — so
  # slurp provides the selection and its `-r` ("restrict to predefined boxes")
  # mode snaps it to real rectangles.
  #
  #  * Monitors stay entirely on DMS: `-o` seeds slurp with one box per output
  #    and `-f '%o'` prints the chosen output's *name*, which is exactly what
  #    `dms screenshot output -o` wants.
  #  * Windows cannot: no `dms screenshot` subcommand accepts a geometry (`-g`
  #    only prints one), so grim captures the rectangle instead. That path alone
  #    loses DMS's wp_color_management/CICP handling, which matters on an HDR
  #    output and is currently moot on this machine's SDR panel.
  #
  # Window rectangles are filtered to the *active workspace*. `hyprctl clients`
  # spans every workspace, and windows on the others report the same geometry as
  # the visible one — feeding those to slurp would offer invisible, overlapping
  # boxes.
  #
  # `dms` and `hyprctl` are left to PATH; pinning dms would drag a second,
  # unpatched copy of the shell into the closure alongside the one the NixOS
  # module builds. The rest are pinned, since they are ordinary tools and the
  # caller's PATH is not this module's to assume.
  screenshot = pkgs.writeShellScriptBin "dms-screenshot" ''
    set -eu
    jq=${pkgs.jq}/bin/jq
    slurp=${pkgs.slurp}/bin/slurp
    grim=${pkgs.grim}/bin/grim
    wlcopy=${pkgs.wl-clipboard}/bin/wl-copy

    if [ "''${1:-}" = menu ]; then
      labels=("Copy Region" "Copy Window" "Copy Monitor" "Save Region" "Save Window" "Save Monitor")
      targets=(region window monitor region window monitor)
      modes=(copy copy copy save save save)
      # Cancelling exits 1, an unreachable shell 2; neither is worth an error.
      i=$(printf '%s\n' "''${labels[@]}" \
        | dms dmenu -p Screenshot --icon screenshot_region --no-custom --format i \
            --mesg "Copy → clipboard · Save → ${screenshotSaveDir}") || exit 0
      [ -n "$i" ] || exit 0
      set -- "''${targets[$i]}" "''${modes[$i]}"
      # The launcher is still animating out when dmenu returns, and
      # `dms screenshot` pre-captures every output immediately, so without this
      # the picker itself lands in the image. There is no "closed" callback.
      sleep 0.35
    fi

    target="''${1:?menu, or a target and copy/save, required}"
    mode="''${2:?copy or save required}"

    dmsshot() {
      case "$mode" in
        copy) exec dms screenshot "$@" --no-file ;;
        save) exec dms screenshot "$@" -d ${screenshotSaveDir} ;;
        *) echo "unknown mode: $mode" >&2; exit 1 ;;
      esac
    }

    case "$target" in
      region)
        dmsshot region
        ;;

      monitor)
        # Cancelling slurp is a normal outcome, not an error.
        name=$("$slurp" -o -r -f '%o') || exit 0
        [ -n "$name" ] || exit 0
        dmsshot output -o "$name"
        ;;

      window)
        ws=$(hyprctl -j activeworkspace | "$jq" -r '.id')
        rects=$(hyprctl -j clients \
          | "$jq" -r --argjson w "$ws" \
              '.[] | select(.mapped and (.hidden|not) and .workspace.id==$w)
               | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
        [ -n "$rects" ] || { echo "no windows on workspace $ws" >&2; exit 1; }

        geom=$(printf '%s\n' "$rects" | "$slurp" -r -f '%x,%y %wx%h') || exit 0
        [ -n "$geom" ] || exit 0

        case "$mode" in
          copy)
            "$grim" -g "$geom" - | "$wlcopy" --type image/png
            ;;
          save)
            # Matches the name DMS gives its own saves.
            out="${screenshotSaveDir}/screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
            mkdir -p "${screenshotSaveDir}"
            "$grim" -g "$geom" "$out"
            "$wlcopy" --type image/png < "$out"
            echo "$out"
            ;;
          *) echo "unknown mode: $mode" >&2; exit 1 ;;
        esac
        ;;

      *) echo "unknown target: $target" >&2; exit 1 ;;
    esac
  '';

  # Screen recording, the screenshot picker's counterpart: `menu` (bound to
  # CTRL+SHIFT+Print) shows the six recording choices through `dms dmenu`, or
  # stops the recording when one is running; the choice is handed to `start`.
  #
  # gpu-screen-recorder rather than wl-screenrec, for the window entry: a
  # geometry-based recorder can only take the rectangle a window occupied when
  # it was picked, which records the wrong thing the moment you change
  # workspace. `-w portal` goes through xdg-desktop-portal-hyprland's share
  # dialog instead and stays on that window wherever it goes. Region and monitor
  # are captured off KMS, which needs the setcap'd gsr-kms-server that
  # modules/nixos/dms installs; without it gsr falls back to a pkexec prompt.
  #
  # The recorder runs as a transient user unit, not a child of whatever started
  # it, so nothing that restarts or kills its caller takes a recording down
  # mid-file. KillSignal=SIGINT is gsr's "stop and save"; KillMode=mixed sends
  # it to gsr alone, so gsr-kms-server is torn down by gsr rather than shot
  # first. ExecStopPost runs `finish` however gsr ended — stopped, crashed, or
  # the portal dialog cancelled — so there is always a closing notification and
  # do-not-disturb is always restored.
  #
  # Do-not-disturb is switched on here rather than left to the hyprland module's
  # screencast listener, because KMS capture bypasses the compositor and
  # Hyprland never reports it. The prior state is handed to `finish` so a DND
  # that was already on stays on. The notifications themselves get through DND
  # by the `Screencast` rule seeded into settings.json below.
  screencastUnit = "dms-screencast";
  screencast = pkgs.writeShellScriptBin "dms-screencast" ''
    set -eu
    gsr=${pkgs.gpu-screen-recorder}/bin/gpu-screen-recorder
    slurp=${pkgs.slurp}/bin/slurp
    wlcopy=${pkgs.wl-clipboard}/bin/wl-copy
    systemctl=${pkgs.systemd}/bin/systemctl
    systemdrun=${pkgs.systemd}/bin/systemd-run
    unit=${screencastUnit}.service

    recording() { "$systemctl" --user is-active --quiet "$unit"; }
    notify() { dms notify "$@" --app Screencast >/dev/null 2>&1 || true; }

    case "''${1:?menu, start or finish required}" in
      menu)
        if recording; then
          exec "$systemctl" --user stop "$unit"
        fi
        labels=("Record Region" "Record Window" "Record Monitor" \
          "Record Region with Audio" "Record Window with Audio" "Record Monitor with Audio")
        targets=(region window monitor region window monitor)
        sounds=(silent silent silent audio audio audio)
        i=$(printf '%s\n' "''${labels[@]}" \
          | dms dmenu -p Record --icon videocam --no-custom --format i \
              --mesg "Saved to ${screenshotSaveDir} · CTRL+SHIFT+Print stops") || exit 0
        [ -n "$i" ] || exit 0
        exec "$0" start "''${targets[$i]}" "''${sounds[$i]}"
        ;;

      start)
        target="''${2:?target required}"
        audio="''${3:?silent or audio required}"

        if recording; then
          exec "$systemctl" --user stop "$unit"
        fi
        # Same reason as the screenshot picker: let the launcher get off screen.
        sleep 0.35

        case "$target" in
          region)
            # DMS's selector prints "X,Y WxH"; gsr wants slurp's "WxH+X+Y" form.
            # Both are logical coordinates — gsr applies the output scale itself.
            # Cancelling prints nothing.
            geom=$(dms screenshot region -g 2>/dev/null) || exit 0
            region=$(printf '%s\n' "$geom" \
              | sed -nE 's/^(-?[0-9]+),(-?[0-9]+) ([0-9]+x[0-9]+)$/\3+\1+\2/p')
            [ -n "$region" ] || exit 0
            source=(-w region -region "$region")
            ;;
          monitor)
            name=$("$slurp" -o -r -f '%o') || exit 0
            [ -n "$name" ] || exit 0
            source=(-w "$name")
            ;;
          window)
            # The portal's own dialog does the picking, inside gsr.
            source=(-w portal)
            ;;
          *) echo "unknown target: $target" >&2; exit 1 ;;
        esac

        case "$audio" in
          silent) sound=() ;;
          # One mixed track: whatever is playing, plus the microphone.
          audio) sound=(-a "default_output|default_input") ;;
          *) echo "unknown audio mode: $audio" >&2; exit 1 ;;
        esac

        # Matches the screenshot naming.
        out="${screenshotSaveDir}/screencast_$(date +%Y-%m-%d_%H-%M-%S).mp4"
        mkdir -p "${screenshotSaveDir}"

        dnd=$(dms ipc call notifications getDoNotDisturb 2>/dev/null || echo false)
        dms ipc call notifications enableDoNotDisturbIndefinitely >/dev/null 2>&1 || true

        # H.264 explicitly: `auto` may pick HEVC, which browsers and Slack do
        # not play, and gsr's man page lists black bars with HEVC/AV1 on AMD.
        "$systemdrun" --user --quiet --collect --unit=${screencastUnit} \
          -p KillSignal=SIGINT -p KillMode=mixed -p TimeoutStopSec=30 \
          -p ExecStopPost="$0 finish $out $dnd" \
          -E PATH="$PATH" \
          "$gsr" "''${source[@]}" "''${sound[@]}" -k h264 -f 60 -o "$out"

        notify "Recording" "CTRL+SHIFT+Print stops and saves" --icon media-record --timeout 2000
        ;;

      finish)
        out="''${2:?}"
        dnd="''${3:-false}"

        [ "$dnd" = true ] \
          || dms ipc call notifications disableDoNotDisturb >/dev/null 2>&1 || true

        if [ -s "$out" ]; then
          # wl-copy has to outlive this unit — it *is* the clipboard until
          # something replaces it, and everything left in a stopped unit's
          # cgroup is killed — so it gets a unit of its own, in the foreground.
          "$systemdrun" --user --quiet --collect --no-block -E PATH="$PATH" \
            "$wlcopy" --foreground --type text/uri-list "file://$out" || true
          notify "Recording saved" "$out" --file "$out" --icon video-x-generic
        else
          rm -f "$out"
          notify "Nothing was recorded" \
            "gpu-screen-recorder ended with ''${SERVICE_RESULT:-?} (''${EXIT_STATUS:-?}); journalctl --user -u $unit" \
            --icon dialog-warning
        fi
        ;;

      *) echo "unknown command: $1" >&2; exit 1 ;;
    esac
  '';

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
  # file below, because `notificationRules` is also where the notification
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
  declaredSettings = {
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
  };
in
mkIf (homeManagerConfig.dms.enable or false) {
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
  # Written out longhand because these files are imported with the NixOS `lib`,
  # which has no `lib.hm.dag`.
  home.activation.dmsSettingsDefaults = {
    after = [ "linkGeneration" ];
    before = [ ];
    data = ''
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
  };

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
  # `lockAtStartup` above).
  xdg.configFile."dms/config.d/10-nix.json".onChange = ''
    ${pkgs.systemd}/bin/systemctl --user try-restart dms.service || true
  '';
  xdg.configFile."dms/config.d/10-nix.json".text = builtins.toJSON declaredSettings;
}
