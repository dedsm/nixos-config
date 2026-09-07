# DankMaterialShell (manwe)

[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) is the desktop shell on the
Linux side: bar, notification centre, control centre, launcher, clipboard history, lock screen and
idle handling, all in one Quickshell process. It replaced five separately-maintained pieces —
waybar, swaync, hyprlock, hypridle, darkman — plus the two tray applets, avizo and clipman.

Two modules configure it:

| Module | Owns |
| --- | --- |
| `modules/nixos/dms` (`dedsm.dms.enable`) | the package, the systemd user service, `/etc/pam.d/dankshell`, the GeoClue app entry, the CLI policy, `adw-gtk3` |
| `modules/common/users/common/dms` (`dms.enable`) | `settings.json` and the vendored theme |

## Packaging

`programs.dms-shell` is a **nixpkgs** module; there is no home-manager module in nixpkgs, which is
why the settings file is written with plain `xdg.configFile`. Upstream also ships its own flake
with both, but mixing its package with the nixpkgs module drops some dependency wiring, so both
come from nixpkgs here. The package is taken from `unstable` (1.5.3) because 26.05 is a release
behind (1.4.6); `quickshell` comes from stable, which satisfies DMS's ">= 0.3.0".

`dgop` (system monitoring), `matugen` (theming) and `khal` (calendar) are pulled in by the module's
feature toggles. `enableCalendarEvents` is off — no khal here.

## settings.json is declarative, session.json is not

`settings.json` is a store symlink, so DMS cannot write it. That is a supported mode: the shell
detects the read-only file, keeps a GUI change live for the session, and the settings modal grows a
**copy settings.json** button that puts the full JSON on the clipboard to be folded back into the
module. Only the keys that differ from upstream defaults are declared — the file has ~530 of them.

`session.json` is deliberately left mutable: it holds runtime state (the current wallpaper, DND,
and `isLightMode` itself). Freezing it would stop the shell persisting the mode at all.

**The light/dark schedule lives there too** (`themeModeAutoEnabled`, `themeModeAutoMode`,
`themeModeStart*`), so it is set once through Settings → Theme rather than in Nix. That is a real
loss of declarativeness against darkman's `usegeoclue = true`, and the only one in this migration.

## Theme

`currentThemeName = "custom"` pointing at `solarized-osaka-night.json`, vendored into the user
module from the official theme registry (by `setiapam`, MIT). It is Solarized where it counts —
`#29a298` cyan, `#268bd3` blue, `#b28500` yellow, `#db302d` red, and Solarized's own base3/base2 in
light mode — over near-black surfaces in dark mode.

DMS drives matugen from that fixed palette rather than from the wallpaper (`matugen color hex`
with the theme's colours imported verbatim), so "dynamic theming" here means *the fan-out*, not
wallpaper-derived colour. What it fans out to, and what this repo keeps for itself, is in
[`theme.md`](./theme.md).

## Authentication

The lock screen's password stack is `/etc/pam.d/dankshell`
(`settings.lockPamExternallyManaged = true`), declared like any other NixOS PAM service. It carries
the gnome-keyring unlock and the `pam_exec` stamp that `dedsm.fingerprintPolicy` needs — without
it, DMS would authenticate against its own user-level config, no stamp would ever be written, and
the policy would drift into permanent denial.

Fingerprint runs in a second, parallel PAM context off DMS's bundled stack
(`lockPamInlineFprint = false`), which keeps the sensor and the password field live at once. It
still goes through fprintd, so the polkit gate governs it either way. See
[`login-flow.md`](./login-flow.md).

## Keybinds

The binds stay in `modules/common/users/common/hyprland/` as `hl.bind` calls; only their targets
moved to `dms ipc call`:

| Bind | Call |
| --- | --- |
| `XF86MonBrightness{Up,Down}` | `brightness increment/decrement 1` — DDC on external monitors, not just the backlight |
| `XF86Audio{Raise,Lower}Volume`, `XF86AudioMute` | `audio increment/decrement/mute` |
| `XF86Audio{Play,Prev,Next}`, `$mod+X/Z/C` | `mpris playPause/previous/next` |
| `$mod+P` | `spotlight toggle` |
| `$mod+V` / `$mod+N` / `$mod+O` | `clipboard` / `notifications` / `control-center` toggle |
| `CTRL+ALT+L` | `loginctl lock-session` (unchanged — DMS listens on logind) |
| `CTRL+ALT+SHIFT+L` | `systemctl --user restart dms.service`, the locked-session escape hatch |

`dms ipc` with no arguments lists every target; the live surface is wider than upstream's
`docs/IPC.md`.

## Things not to do

- **`dms setup`, `dms setup binds`, `dms setup colors`, `dms greeter install`** write compositor
  configs and system units directly. `/etc/dms/cli-policy.json` declares this system immutable and
  DMS refuses them outright.
- **Its display settings panel** — `hyprdynamicmonitors` owns monitor profiles here.
- **Its icon-theme picker** — `icon-theme` is declared statically as `Papirus` in the `defaults`
  module, and a runtime write would be reset on the next activation. Same failure mode as the two
  dconf keys in [`theme.md`](./theme.md).
- **`input` group membership** for the evdev warning in `dms doctor`: it buys a caps-lock indicator
  and costs read access to every input device for anything running as this user.

## Screencast and notifications

`screencast-inhibit` (hyprland module) watches Hyprland's socket2 for `screencast>>1` / `>>0` and
calls `dms ipc call notifications enableDoNotDisturbIndefinitely` / `disableDoNotDisturb`. DMS
detects screencasts itself (`PrivacyService`, from PipeWire) but only renders an indicator — the
notification service consults `doNotDisturb` and nothing else, so the automation is still ours.

## Debugging

```bash
dms doctor                       # environment sanity check: versions, portals, fonts, services
dms ipc                          # list every IPC target
journalctl --user -u dms -f      # shell log, including matugen runs and theme builds
dms ipc call lock isLocked
```
