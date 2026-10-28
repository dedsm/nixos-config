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
{ pkgs, screenshotSaveDir }:
pkgs.writeShellScriptBin "dms-screenshot" ''
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
''
