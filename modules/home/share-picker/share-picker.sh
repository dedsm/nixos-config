# xdph runs this in place of hyprland-share-picker and reads the choice from
# stdout. Nothing else may print there. See docs/share-picker.md.
preview=0
allow_token=0
for arg in "$@"; do
  case "$arg" in
  --preview) preview=1 ;;
  --allow-token) allow_token=1 ;;
  esac
done

runtime="${XDG_RUNTIME_DIR:-/tmp}/share-picker"
mkdir -p "$runtime"

# --preview: what xdph would pass, to try the overlay without sharing anything.
if [ "$preview" = 1 ]; then
  XDPH_WINDOW_SHARING_LIST="$(hyprctl -j clients | jq -r '.[] | select(.mapped) | "\(.address)\t\(.class)\t\(.title)"' |
    while IFS=$'\t' read -r address class title; do
      printf '%d[HC>]%s[HT>]%s[HE>]%d[HA>]' "$((address & 0xFFFFFFFF))" "$class" "$title" "$address"
    done)"
  export XDPH_WINDOW_SHARING_LIST
fi

# Chromium and Electron can ask several times for one share. Answer the repeats
# from the first choice, and queue them behind an open picker.
exec 9>"$runtime/lock"
flock 9
last="$runtime/last"
gap=none
if [ -s "$last" ]; then
  gap=$(($(date +%s) - $(stat -c %Y "$last")))
fi
# Each prompt's gap since the last choice, to size this window from real shares.
if [ "$preview" = 0 ] && [ "$gap" != none ] && [ "$gap" -lt 4 ]; then
  printf '%s gap=%ss reused\n' "$(date +%T)" "$gap" >>"$runtime/prompts"
  cat "$last"
  echo
  exit 0
fi
if [ "$preview" = 0 ]; then
  printf '%s gap=%ss asked\n' "$(date +%T)" "$gap" >>"$runtime/prompts"
fi

out="$(mktemp "$runtime/out.XXXXXX")"
trap 'rm -f "$out"' EXIT

PICKER_OUT="$out" \
  PICKER_ALLOW_TOKEN="$allow_token" \
  PICKER_MONITORS="$(hyprctl -j monitors)" \
  PICKER_CLIENTS="$(hyprctl -j clients)" \
  quickshell --no-color -p "@shellDir@/shell.qml" >"$runtime/log" 2>&1 || true

choice="$(cat "$out")"
case "$choice" in
"[SELECTION]"*)
  if [ "$preview" = 0 ]; then
    printf '%s' "$choice" >"$last"
  fi
  # xdph takes the selection up to the end of the line.
  printf '%s\n' "$choice"
  ;;
CANCEL)
  # No selection: xdph refuses the share.
  ;;
*)
  # The overlay failed to run. Sharing must still work.
  if [ "$preview" = 0 ]; then
    exec hyprland-share-picker "$@"
  fi
  echo "the overlay failed; see $runtime/log" >&2
  exit 1
  ;;
esac
