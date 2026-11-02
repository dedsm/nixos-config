# Screen share picker

`dedsm.sharePicker` (`modules/home/share-picker`) replaces `hyprland-share-picker`, the dialog
xdg-desktop-portal-hyprland (xdph) shows when anything asks to share the screen. It's an overlay in the style of
macOS: both screens dim, every visible window gets a **Share This Window** button, every screen gets **Share Entire
Screen**, and a list holds windows on other workspaces. `Esc` or **Cancel** refuses the share.

It covers everything that goes through the portal: browsers, Slack, the window entry of `dms-screencast`, and Hex's
Annotate.

## How it plugs in

xdph runs the program named by `custom_picker_binary` in `~/.config/hypr/xdph.conf`, gives it the window list in
`XDPH_WINDOW_SHARING_LIST`, and reads the choice from stdout. `share-picker.sh` is that program, and `shell.qml` is the
overlay it starts in Quickshell, the same package as Dux Shell. The output is what the stock picker prints, so apps
can't tell the difference:

```
[SELECTION]/window:1468270128
[SELECTION]/screen:DP-3
```

An `r` after `[SELECTION]` allows a restore token. It's only added if xdph passes `--allow-token`, which it doesn't
here, so every share asks.

xdph reads its config once, so activation restarts it when the file changes, which ends any share in progress.

## Decisions

- **Windows are matched by address.** xdph's list includes each window's Hyprland address, which the overlay joins to
  `hyprctl clients` for its position. Class and title are the fallback when xdph has no address.
- **Keyboard focus is on demand, not exclusive.** Exclusive focus keeps the pointer on one screen. Hyprland focuses an
  on-demand layer when it maps, so `Esc` still works.
- **A failure falls back.** If the overlay doesn't run, the stock picker opens, so sharing keeps working. The overlay
  writes `CANCEL` when refused, which is how the script tells a cancel from a crash. The stock picker floats, through
  `float-share-picker` in `modules/home/hyprland`, for the reason in [`docs/hex.md`](./hex.md#annotate).
- **Repeats reuse the first choice.** Chromium and Electron can ask several times for one share, so the script
  serializes prompts and answers from the last choice for 4 seconds. A new share started within those 4 seconds gets
  the same answer, because xdph doesn't tell the picker which app is asking. `$XDG_RUNTIME_DIR/share-picker/prompts`
  records each prompt's gap since the last choice and whether it was reused, which is what to size the window from.

## Limits

- No region or workspace selection, which the stock picker has.
- Neutral dark colours, not the Dux Shell theme.
- A floating window can cover the button of one behind it. Clicks go to the one on top.
- Hyprland only, because of `hyprctl`.

## Trying and debugging

`share-picker --preview` opens the overlay from a terminal with a list like xdph's and prints the choice, without
sharing anything. If it sticks, `pkill -f share-picker-shell` closes it. Don't kill `quickshell` by name, because that
also kills Dux Shell.

The overlay's last log is `$XDG_RUNTIME_DIR/share-picker/log`. `journalctl --user -u xdg-desktop-portal-hyprland` shows
each `[sc] Selection:` line, though xdph's output can arrive late.
