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
# by the `Screencast` rule default.nix seeds into settings.json.
{ pkgs, screenshotSaveDir }:
let
  screencastUnit = "dms-screencast";
in
pkgs.writeShellScriptBin "dms-screencast" ''
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
''
