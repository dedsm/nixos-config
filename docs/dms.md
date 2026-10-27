# DankMaterialShell (manwe)

[DankMaterialShell](https://github.com/duxlabs-dev/dux-shell) is the desktop shell on the Linux
side: bar, notification centre, control centre, launcher, clipboard history, lock screen and idle
handling, all in one Quickshell process. It replaced five separately-maintained pieces — waybar,
swaync, hyprlock, hypridle, darkman — plus the two tray applets, avizo and clipman.

With 2.0 the project moved from AvengeMedia to Dux Labs and is now "Dux Shell": nixpkgs renamed the
package `dux-shell` (and the greeter `dux-greeter`), and the shell moved its config, state and cache
from `DankMaterialShell` to `dms` (`~/.config/dms`, `~/.local/state/dms`, `~/.cache/dms`), leaving
the old names behind as symlinks. The binary is still `dms`, the unit still `dms.service`, and
26.05's NixOS module is still `programs.dms-shell` — it becomes `programs.dux-shell` with 26.11.

Two modules configure it:

| Module | Owns |
| --- | --- |
| `modules/nixos/dms` (`dedsm.dms.enable`) | the package and its Quickshell, the systemd user service, `/etc/pam.d/dankshell`, the GeoClue app entry, the CLI policy, `adw-gtk3` |
| `modules/common/users/common/dms` (`dms.enable`) | the declared settings (`config.d/10-nix.json`, in `settings.nix`), the seeds for `settings.json` and `session.json` (`default.nix`), the vendored theme, the screenshot and recording pickers (`screenshot.nix`, `screencast.nix`) |

## Packaging

`programs.dms-shell` is a **nixpkgs** module; there is no home-manager module in nixpkgs, which is
why the settings file is written with plain `xdg.configFile`. Upstream also ships its own flake
with both, but mixing its package with the nixpkgs module drops some dependency wiring, so both
come from nixpkgs here. The package is taken from `unstable` (`dux-shell` 2.0.0) because 26.05 is
a major release behind (1.4.6).

**Quickshell has to come from `unstable` too** (`programs.dms-shell.quickshell.package`). The
package wraps QML modules into the shell's environment — kirigami, sonnet, qtmultimedia,
kimageformats — and those are unstable's, built on Qt 6.12. Stable's Quickshell 0.3.0 is built on
Qt 6.11, and Qt refuses to load a plugin from a different build: the journal said
`libquickmultimediaplugin.so uses incompatible Qt library. (6.12.0)` followed by
`QtMultimedia not available`, and the shell ran without it. Nothing else complained, which is the
trap — a Qt split shows up only as features that quietly are not there. With both on unstable the
journal instead says `Using Qt multimedia with FFmpeg`, and `dms doctor` reports the Quickshell
version. The greeter's Quickshell follows this option by default, so it is covered too; so is the
`qtengine` platform theme the unit loads (see [`theme.md`](./theme.md)), which comes from unstable
as well. If the two inputs are ever bumped separately, check the Qt versions match:

```bash
nix eval --raw .#nixosConfigurations.manwe.pkgs.unstable.qt6.qtbase.version
```

One `overrideAttrs` sits on top, carrying one patch: it removes the
`pkill -HUP -f 'gtk'` that ends `updateGtkIconTheme` in `Common/SettingsData.qml`. It was meant to
make GTK apps re-read `settings.ini`, but GTK does not handle SIGHUP, so it *kills* every process
whose command line contains "gtk" — chiefly `xdg-desktop-portal-gtk`. With `iconThemePerMode` on
(see [`theme.md`](./theme.md#the-icon-theme-is-a-third-dms-owned-key)) that ran on every light/dark
transition, at the very moment the portal should have been broadcasting the new `color-scheme`, so
Firefox missed each change and sat one mode behind — dark in light mode and vice versa. GTK apps
already get the icon theme live through the portal. It uses `--replace-fail`, so an upstream
change to the anchor is a build error rather than a silent no-op; the line is still there in 2.0.0.
Nothing else about the package is patched. (Up to 1.6.2 there were two more, on the fingerprint
path; 1.6.3 fixed that bug upstream — see
[the duty-cycle note below](#the-fingerprint-reader-was-dead-half-the-time).)

**The patch runs in `preBuild`, against the source tree, and then re-runs `make sync-shell`.** As
of 1.6.x the QML shell is no longer installed as files: nixpkgs builds with upstream's `withshell`
tag, and `sync-shell` copies `quickshell/` into `core/internal/shellembed/dist` to be `go:embed`ed
into the `dms` binary. `$out/share/quickshell` does not exist any more, so the `postInstall`
substitutions these started life as had nothing to bite on — which is exactly how the 1.5.3 → 1.6.2
bump announced itself, as `substitute(): ERROR: file ... does not exist`. Re-running `sync-shell` is
safe (it is an `rm -rf` plus a fresh copy) and is what keeps the edit honest: it recomputes the
`.dankrev` content hash that names the directory the shell extracts itself into at runtime
(`$XDG_RUNTIME_DIR/dms-shell/<dankrev>/`). Editing the embed dir in place would leave that hash
stale and let a previously-extracted copy win. The re-run needs a `chmod -R u+w` first, because
nixpkgs' own `sync-shell` has already left a copy carrying the store's read-only permissions.

26.05's module still has v1's feature toggles, each pulling in a helper. Two are built into the 2.0
binary — unstable's module removed them for that reason — so `enableSystemMonitoring` (a stale
`dgop` 0.2.2) and `enableClipboardPaste` (`wtype`) are off. `matugen` (theming) and `cava` stay;
unstable's module installs both by default. `enableCalendarEvents` is off — no khal here. All of
this goes away with the 26.11 module.

## Settings: a declared `config.d/` drop-in over a writable `settings.json`

Since 2.0 DMS loads `settings.json` and then every `config.d/*.json` over it, in lexicographic
order, later files winning — and saves a GUI change back to **whichever file the key came from**,
writing a file only when its own keys changed. The user module uses that split:

- `~/.config/dms/config.d/10-nix.json` is a store symlink holding everything declared. A GUI change
  to one of those keys is live for the session only (its write fails, and is retried), and is gone
  at the next shell restart.
- `~/.config/dms/settings.json` is an ordinary file the shell owns. A GUI change to any key *not*
  declared persists there, like on any other distro.

Before 2.0 the whole of `settings.json` was the store symlink, so every GUI change was lost. To
fold a GUI change into the declaration, read it from `settings.json` (or from
`dms ipc call settings dump`, which prints the merged view) and move it into the module.

Mostly only the keys that differ from upstream defaults are declared — upstream has ~540 of them —
with a handful pinned at their default on purpose (`lockAtStartup`, `lockPamExternallyManaged`,
`lockPamInlineFprint`, `runUserMatugenTemplates`, the two suspend timeouts), because each is
load-bearing enough that a default flip upstream should not be silent. Upstream's defaults are the
`def` fields in `Common/settings/SettingsSpec.js` — read from upstream's source tree, or from the
copy the shell extracts to `$XDG_RUNTIME_DIR/dms-shell/<dankrev>/`, since nothing is installed.
Two caveats when diffing against a dump: a `property color` is dumped as a QColor object rather
than the `"#rrggbb"` string it defaults to, so those always look changed; and `barConfigs` is
rebuilt by the bar settings tab from only the fields that tab edits, so a dumped copy comes back
with keys *missing*. Declare `barConfigs` from upstream's default with your overrides applied,
never by pasting the dump.

### The declared file must be in the current schema

The settings carry a `configVersion` (42 for 2.0.0), and a file below the shell's version is
migrated **on every load**. Since 2.0 the migration's result is also saved straight away — which,
for a read-only file, fails. Until the declaration was rewritten, the old pre-2.0 file had no
`configVersion` at all, so every shell start ran all 42 migrations from v0 and logged
`Write of .../settings.json failed: Permission denied`. The migrations were faithful, so nothing
*looked* wrong; that log line was the only sign.

2.0 also moved widget options from global keys onto each widget instance in `barConfigs` — the
workspace pills' `showWorkspaceIndex`/`showWorkspaceApps`/`workspaceActiveAppHighlightEnabled` are
options on the `workspaceSwitcher` entry, the mic percentage and idle-inhibitor indicator on
`controlCenterButton` — gave the control centre a real grid (`w`/`h` cells instead of `width`),
and replaced `cornerRadius` with `radiusStrength` (12 maps to 38). When upstream bumps
`configVersion` again, look for `Migrating settings from version` in the journal, run the shell
once, and regenerate the affected keys from `dms ipc call settings dump` — `barConfigs` excepted,
as above.

`controlCenterWidgets` is no longer declared. It used to be, only to add the "Keep Awake"
(`idleInhibitor`) tile — waybar's `idle_inhibitor` — which upstream's default lacked before 2.0
and now includes. Left undeclared, the control centre takes upstream's layout (which also has Do
Not Disturb, battery and disk tiles), and an edit made in its GUI persists in `settings.json`.

### Notification rules are seeded, not declared

`notificationRules` is also where the notification context menu writes: "mute this app",
"mute for 1 hour / 4 hours" (a rule with an expiry), and the per-app "allow during DND" toggle.
Declared in the read-only file, all of those would be lost at the next restart. So the one rule
this repo needs — `Screencast` bypassing DND, see [Screen recording](#screen-recording) — is
instead merged into `settings.json` by an activation script (ordered after `linkGeneration`), which
adds it when no rule matches the same field and pattern and leaves every other rule alone. It also
creates `settings.json` if there is none, and removes a leftover store symlink in its place —
otherwise merging into it would copy every old declared key into the live file.

### `session.json`

`session.json` is deliberately left mutable: it holds runtime state (the current wallpaper, DND,
and `isLightMode` itself). Freezing it would stop the shell persisting the mode at all.

**The light/dark schedule lives there too** (`themeModeAutoEnabled`, `themeModeAutoMode`,
`themeModeStart*`, `themeModeShareGammaSettings`), and its default is *off* — so the migration silently dropped the automatic
switching darkman did until this was noticed. The user module now seeds them on
activation with a jq merge (`.[0] + .[1]`, defaults on the left, existing state on the right), so a
fresh machine gets sunrise/sunset switching while anything already set is never overwritten. It is
still weaker than declaring them: turn the schedule off in the GUI and the config will not put it
back.

`themeModeShareGammaSettings` is seeded to `false` for a specific reason: it defaults to *true*,
pointing the light/dark schedule at gamma control's settings, and gamma control is manual here — so
it has no schedule to share and the automation computes transitions from nothing. The symptom was a
next transition ten minutes away, dark in the middle of the afternoon, and light/dark flapping
within seconds of each other.

### A rebuild restarts the shell

A change to the declared settings does not reach a running shell on its own. DMS watches each
settings file (`watchChanges` on its FileView, plus a folder model on `config.d`), but home-manager
re-links with `ln -Tsf`, replacing the *symlink* rather than the file, so the inode being watched
never changes and no event fires. This was tested on 2.0.0 by re-linking `10-nix.json` exactly that
way: the running shell kept the old value. (An in-place edit of the real `settings.json`, by
contrast, is picked up live.) The file entry therefore carries an `onChange` hook that runs
`systemctl --user try-restart dms.service` — safe only because nothing locks the screen on shell
start (see below).

### Wellbeing is off

Digital Wellbeing, new in 2.0 and **on by default**, records how long each app holds focus (into
`~/.local/state/dms/wellbeing/db`) to back daily and per-app screen-time limits. It is declared off
(`wellbeingEnabled = false`), and the data it gathered before that was deleted;
`dms ipc call wellbeing status` should say "Screen time tracking: disabled".

## Theme

`currentThemeName = "custom"` pointing at `solarized-osaka-night.json`, vendored into the user
module from the official theme registry (by `setiapam`, MIT). It is Solarized where it counts —
`#29a298` cyan, `#268bd3` blue, `#b28500` yellow, `#db302d` red, and Solarized's own base3/base2 in
light mode — over near-black surfaces in dark mode.

DMS drives matugen from that fixed palette rather than from the wallpaper (`matugen color hex`
with the theme's colours imported verbatim), so "dynamic theming" here means *the fan-out*, not
wallpaper-derived colour. What it fans out to, and what this repo keeps for itself, is in
[`theme.md`](./theme.md).

### `customThemeFile` must be a store path in its own right

The setting is a *path in a JSON file*, and it has to be written as `"${theme}"` — never
`toString theme`. `toString` on a relative path yields the file's location inside the flake source
(`/nix/store/<hash>-source/modules/common/users/common/dms/solarized-osaka-night.json`) as a plain
string, and a plain string buys no store reference: Nix registers a reference only for a hash that
belongs to the derivation's own inputs, and the source tree is not an input of the settings
file's derivation (`config.d/10-nix.json` since 2.0, `settings.json` before). The rendered file ends up with **no references at all**, so the next garbage collection
deletes the `-source` path out from under a config that is still live, leaving a dangling pointer.

Interpolating instead copies the JSON into the store as
`/nix/store/<hash>-solarized-osaka-night.json` and registers it, which is what makes GC respect it.
Verify with:

```bash
nix-store -q --references "$(readlink -f ~/.config/dms/config.d/10-nix.json)"
# must print the solarized-osaka-night.json store path; empty output is the bug
```

The failure is quiet and badly disguised: DMS logs one `WARN qml: [Theme:1873] Theme data not
available for: custom` and then simply *stops building themes*. No dconf write, no matugen run — so
`~/.local/state/theme/mode`, foot and tmux all freeze at whatever the last successful transition
wrote, `dms ipc call theme getMode` drifts away from the marker file, and
`/org/gnome/desktop/interface/color-scheme` is left wherever it last landed (`'default'` once
home-manager's dconf-cleanup pass has reset it, which makes the portal answer `0` — "no preference"
— and drops Firefox and Slack to light).

## Authentication

The lock screen's password stack is `/etc/pam.d/dankshell`, declared like any other NixOS PAM
service. It carries the gnome-keyring unlock and the `pam_exec` stamp that
`dedsm.fingerprintPolicy` needs — without it, DMS would authenticate against its own user-level
config, no stamp would ever be written, and the policy would drift into permanent denial.

Getting DMS to use that file is counter-intuitive, and cost an evening:

- **`lockPamExternallyManaged` must be off.** It reads like "the admin declares the stack"; it
  actually means "authenticate against `/etc/pam.d/login`", which is password-only here by design —
  *and* it suppresses the parallel fingerprint context. On, it disables fingerprint unlock twice
  over.
- **`lockPamPath` names the stack outright.** Left on `Auto`, DMS resolves through a fallback chain
  (custom path → `login` if externally managed → `dankshell` *if that file happens to exist* → a
  generated user-level one). Pinning `/etc/pam.d/dankshell` removes the inference.

Fingerprint runs in a second, parallel PAM context off DMS's bundled stack
(`lockPamInlineFprint = false`), which keeps the sensor and the password field live at once. It
still goes through fprintd, so the polkit gate governs it either way.

**`DMS_FORCE_FPRINT_AVAILABLE=1`** is set on the unit, and is load-bearing: DMS decides *once at
startup* whether a reader exists by running `fprintd-list`, which needs the polkit action
`net.reactivated.fprint.device.verify` — exactly what the policy denies after a boot. The probe
therefore failed on every boot, and the sensor was never offered again for the whole session, hours
after the policy would have allowed it. The flag skips the probe so the decision happens at verify
time, where the gate is re-evaluated per attempt. See [`login-flow.md`](./login-flow.md).

### The fingerprint reader was dead half the time

**Fixed upstream in 1.6.3; this repo patched it locally until then.** Kept because the symptom is
easy to mistake for the policy.

Symptom: fingerprint unlock "works sometimes". `fingerprint-status -v` says the window is wide
open, the journal shows no polkit denial, and yet touching the sensor often does nothing at all.

It was not the policy but a duty cycle. Up to 1.6.2, three upstream behaviours composed into it:

1. `assets/pam/fprint` passed no `timeout=`, so pam_fprintd gave up on a verify after its default
   30 seconds and returned `PAM_AUTHINFO_UNAVAIL`.
2. DMS classified that as `PamResult.Error` — not "nobody touched it" — and re-armed on an
   exponential backoff capped at 30 seconds (`Modules/Lock/Pam.qml`).
3. `errorTries` was reset only when the lock opened and on a settings change — not on wake, on
   activity, or on a keypress.

So roughly two minutes into any lock the sensor settled into 30s armed, 30s unclaimed,
indefinitely, with the fingerprint icon lit either way (see
[`login-flow.md`](./login-flow.md#what-the-lock-screen-shows)). The journal showed it as a
`Starting pam session ... with config "fprint"` every 60 seconds and a `Verification timed out`
exactly 30 seconds after each:

```bash
journalctl -b -S "-2h" | grep -E 'Starting pam session|timed out|Failed to match|Screen lock active'
```

This repo worked around it with `timeout=600` on the PAM stack and the backoff cap lowered to 3s,
which got the duty cycle to ~99.5%, but neither knob touched the actual defect: a timeout with
nobody present is not an error. 1.6.3 fixes exactly that, which is why both patches are gone:

- The bundled stack now passes `max-tries=1 timeout=90`, and `Pam.qml` mirrors it in
  `sessionTimeoutMs`.
- An `Error` from a context that lived out (nearly) that timeout — measured from pam_fprintd's
  first message, so a slow claim cannot pass for one — is treated as an expiry: `errorTries` is
  reset and a new attempt starts at once. The reader is armed for the whole lock, minus the
  re-claim.
- Genuine faults retry on a fixed schedule — 1.5s, then 35s (past fprintd's 30s idle exit, so a
  daemon wedged by a suspend has gone away), then every 60s, 200 times — and `recover()` resets the
  counter on resume, lid open and lock-screen activity.

The policy gate's tail shrinks with it. polkit is consulted on `VerifyStart`, so an attempt armed
just before a policy window lapses stays usable until it ends: now at most 90 seconds, against
windows of 48 and 156 hours. (This is also why `timeout=-1`, which `pam_fprintd(8)` documents as
"always active while this module is loaded", would be wrong here: with no timeout there is never a
second `VerifyStart`, so on an untouched machine the gate would be consulted once at lock time and
never again.)

A no-match is a different thing and is not a bug: `Failed to match fingerprint` in the log means
the sensor *did* read a finger and rejected it, and it counts against both `maxFprintTries` and the
policy's `failureLimit`.

### What it costs in power

Holding a verify open pins the reader out of USB runtime suspend — measured at 63.9s active out of
64s wall during a claim, against `control=auto` and a 2s autosuspend delay otherwise. The draw
itself is **below what this machine can resolve**: system noise over a two-minute run is ~640 mW
with ~1 W of drift between baselines, so the delta comes out as noise. The real bound is the USB
descriptor — `bMaxPower = 100mA` on a 5 V bus, so **500 mW, ceiling**. Ten minutes at that ceiling
is 83 mWh against a ~48 Wh pack (`charge_full` 3.119 Ah at 15.39 V), or 0.17%; holding the reader
for the whole lock rather than half of it costs ≈0.5%/hour worst case and realistically far less. It is zero
while suspended: fprintd takes a sleep *delay* inhibitor and releases the device before sleep, so
none of this touches the s2idle drain floor in [`hibernation.md`](./hibernation.md).

## Keybinds

The binds stay in `modules/common/users/common/hyprland/` as `hl.bind` calls; only their targets
moved to `dms ipc call`:

| Bind | Call |
| --- | --- |
| `XF86MonBrightness{Up,Down}` | `brightness increment/decrement 1 ""` — DDC on external monitors, not just the backlight |
| `XF86Audio{Raise,Lower}Volume`, `XF86AudioMute` | `audio increment/decrement/mute` |
| `XF86Audio{Play,Prev,Next}`, `$mod+X/Z/C` | `mpris playPause/previous/next` |
| `$mod+P` | `spotlight toggle` |
| `$mod+V` / `$mod+N` / `$mod+O` | `clipboard` / `notifications` / `control-center` toggle |
| `$mod+SHIFT+N` | `notifications invokeLast` — the newest notification's default action, as clicking it would |
| `CTRL+ALT+L` | `loginctl lock-session` (unchanged — DMS listens on logind) |
| `XF86PowerOff` | `powermenu toggle` — the power button's short press; see below |
| `CTRL+ALT+SHIFT+L` | `systemctl --user restart dms.service`, the locked-session escape hatch |
| `Print` | `dms screenshot region --no-file` — region to clipboard, no file |
| `CTRL+Print` | `dms-screenshot menu` — the screenshot picker, see below |
| `CTRL+SHIFT+Print` | `dms-screencast menu` — the recording picker, or stop-and-save while recording — see below |

`dms ipc` with no arguments lists every target; the live surface is wider than upstream's
`docs/IPC.md`.

The power button needs more than a bind. logind acts on `KEY_POWER` itself, straight off the evdev
node, so with its default `HandlePowerKey=poweroff` the machine shuts down whatever the compositor
binds — and DMS takes no `handle-power-key` inhibitor that would stop it. `modules/nixos/dms` sets
`HandlePowerKey=ignore` so the short press is the bind's alone, and keeps
`HandlePowerKeyLongPress=poweroff`: holding the button still shuts down from the lock screen and the
greeter (neither can open the menu — the bind is not `locked`, and the greeter has no Hyprland
session) or with the shell wedged. Disabling `dedsm.dms` hands the button back to logind.

Mind the arity. `brightness increment` documents its device as optional but the running signature is
`increment(step: string, device: string)`, so the bind passes `""` (the default backlight) — with
one argument it fails, and a bind's `exec_cmd` failure goes nowhere, so the key simply does nothing.
`audio increment/decrement` really does take only the step; everything else above is a
zero-argument toggle.

## Screenshots, and the picker

`dms screenshot` replaced hyprshot. It is its own `wlr-screencopy` client, so it needs neither
`grim` nor `slurp` for its own modes, and it adds several things hyprshot had no equivalent for:
`scroll` mode, which stitches a scrolled region into one tall image; JPEG/PPM output with a quality
knob; a remembered last region (`last`, `--reset`); `--json` metadata and `-g` to print a geometry
without capturing; and — the one that silently mattered — HDR handling, reading
`wp_color_management_v1` and writing H.273 CICP code points into the PNG, where `grim` has no
concept of colour encoding at all. The frozen backdrop hyprshot made opt-in with `-z` is
unconditional (`preCaptureAllOutputs`). 2.0 added Ctrl+C in the region selector (copy without
saving), snapping the region to DMS's own popouts and modals, and `--hud` to scale or hide the
selector's readout.

The picker on `CTRL+Print` is `dms-screenshot menu`, a script the user module puts on PATH. It
pipes six entries — region, window and monitor, each as copy and save — into **`dms dmenu`**,
which shows them in the launcher and prints the chosen one (`--format i` returns its index, so
the labels can change freely). `dms-screenshot <target> <copy|save>` captures directly, without
the menu. After a pick it waits 0.35s before capturing: the launcher is still animating out, and
`dms screenshot` pre-captures every output at once, so the picker would otherwise land in the image.

`dms dmenu` is new in 2.0. Before it, spotlight had no stdin mode at all — its IPC surface could
open, filter and prefill, but returned nothing to the caller — so the list was a DMS **launcher
plugin**, which needed a `plugin_settings.json` seed to be enabled at all and a purge of Qt's
compiled-QML cache on every change (Qt validates that cache by mtime, and every store file carries
the same one, so an edited plugin kept running its previous version). Both plugins and all of that
went with the switch; they were also reachable by typing `#` or `!` in the launcher, which nothing
here uses.

**Window and monitor open a picker**, as `hyprshot -m window` and `-m output` did (`-m active` was
the modifier meaning "the focused one"; these were never the active-only forms). DMS has no picker
to offer: `dms screenshot window` only ever captures the active window, `output` requires an
explicit `-o <name>`, the region selector snaps only to DMS's own surfaces, and no subcommand
accepts a geometry — `-g` only *prints* one. So **slurp** provides the selection, its `-r`
("restrict to predefined boxes") mode snapping it to real rectangles:

- **Monitors stay entirely on DMS.** `slurp -o` seeds one box per output and `-f '%o'` prints the
  chosen output's *name*, which is exactly what `dms screenshot output -o` takes.
- **Windows cannot.** Nothing in `dms screenshot` accepts a geometry, so `grim -g` captures the
  rectangle and `wl-copy` puts it on the clipboard. That path alone loses DMS's
  `wp_color_management`/CICP handling — it matters on an HDR output and is moot on this machine's
  SDR panel. It is also why `grim`, `slurp` and `wl-clipboard` are load-bearing rather than merely
  installed.

Window rectangles are filtered to the **active workspace**. `hyprctl clients` spans every
workspace, and windows on the others report the same geometry as the visible one, so feeding the
unfiltered list to slurp offers invisible, overlapping boxes.

## Screen recording

The same mechanism, for video: `dms-screencast`, a script the dms home-manager module puts on
PATH. There is one key, `CTRL+SHIFT+Print`, running `dms-screencast menu`: with nothing recording
it shows the six choices through `dms dmenu` and hands the pick to `dms-screencast start`; while a
recording runs it stops it and saves the file.

Six entries: region, window and monitor, each **silent** or **with audio**. Copy/save, the
screenshot picker's second axis, has no useful meaning for video, so every recording is saved, to
`~/Downloads/screencast_<date>.mp4` beside the screenshots. "With audio" is one mixed track of the
default output (whatever is playing) and the default input (the microphone).

The recorder is **gpu-screen-recorder**, encoding H.264 on the GPU. H.264 is set explicitly because
`auto` may choose HEVC, which browsers and Slack do not play, and gsr's own man page lists black bars
with HEVC/AV1 on AMD. It was chosen over wl-screenrec for the window entry alone:

- **Window** is `-w portal`. xdg-desktop-portal-hyprland's share dialog picks the window, and the
  capture is tied to that window, not to a rectangle, so it keeps recording it across workspaces
  and moves. A geometry-based recorder, the only kind wl-screenrec is, would record whatever ended up
  in the rectangle the window occupied when picked. Expect a hidden window to freeze on its last
  frame: many apps stop redrawing when they think nobody can see them.

  This only works because `modules/nixos/hyprland` patches xdg-desktop-portal-hyprland with upstream
  [`ba31964`](https://github.com/hyprwm/xdg-desktop-portal-hyprland/commit/ba31964ee42b56bcb0d3b78a64ead5d8a1c3c6f6).
  Stock xdph, up to and including 1.4.1, hands PipeWire consumers only the first plane of each
  dma-buf. This iGPU's compositor buffers use DCC modifiers, which carry extra metadata planes, so gsr
  could not import a single frame: "failed to create egl image with modifier 0x2000000104abb04",
  renegotiation through each DCC modifier in turn, then "no more input formats". The same patched
  package is the home-manager `portalPackage` too, so no stock copy is left installed. An assertion
  fires once nixpkgs ships a release newer than 1.4.1, which may already include the fix.
- **Region** reuses DMS's own selector through `dms screenshot region -g`, which prints the geometry
  without capturing. Its `X,Y WxH` is reformatted into gsr's slurp-style `WxH+X+Y`. Both are logical
  coordinates; gsr applies the output scale itself (`main.cpp`, `monitor_scale_inverted`), so the
  1.33 panel needs no conversion here.
- **Monitor** is the screenshot picker's `slurp -o -r -f '%o'`. gsr's monitor names are the DRM
  connector names, which match Hyprland's.

Region and monitor are captured off **KMS**, which needs `CAP_SYS_ADMIN`.
`programs.gpu-screen-recorder.enable` in `modules/nixos/dms` installs `gsr-kms-server` as a setcap
wrapper; without it, each of those recordings stops at a pkexec prompt. The cost is that any local
process can read the screen through that wrapper. On a single-user laptop that adds little to what
Hyprland's screencopy already gives every Wayland client.

The recorder runs as the transient user unit `dms-screencast.service`, not as a child of whatever
started it. When the picker was a launcher plugin, `execDetached` left its children in
`dms.service`'s cgroup, where restarting the shell — which every rebuild does — killed a recording
mid-file; the unit keeps it independent of its caller either way. Its properties carry the rest:

- `KillSignal=SIGINT` is gsr's "stop and save", so `systemctl --user stop` finalises the file.
- `KillMode=mixed` sends that signal to gsr alone, letting gsr tear down its `gsr-kms-server`
  child itself.
- `ExecStopPost` runs `dms-screencast finish` however gsr ended — stopped, crashed, or the portal
  dialog cancelled — so there is always a closing notification ("Recording saved", with DMS's
  Open / Open Folder actions, or "Nothing was recorded" with the journal command). The file is also
  put on the clipboard as a `text/uri-list` file reference. That `wl-copy` runs in a transient unit
  of its own, because wl-copy *is* the clipboard until something replaces it, and everything left in
  a stopped unit's cgroup is killed.

**Do-not-disturb** is switched on for the duration and restored afterwards: turned off again only if
it was off before. The hyprland module's `screencast-inhibit` listener cannot do this here, because
KMS capture bypasses the compositor and Hyprland never reports it. Window recordings go through the
compositor, so the listener fires for those too, and its unconditional `disableDoNotDisturb` at the
end wins over a DND you had on before. The recorder's own notifications get through DND by the
`Screencast` rule in `notificationRules`, seeded into `settings.json` (see
[Notification rules are seeded](#notification-rules-are-seeded-not-declared)). The "Recording"
notification is sent just after capture starts, so it shows in the first two seconds of a video whose area covers the
notification corner.

## Things not to do

- **`dms setup`, `dms setup binds`, `dms setup colors`, `dms greeter install`** write compositor
  configs and system units directly, and **`dms update` / `dms switch`** (new in 2.0) replace the
  installed packages in place. `/etc/dms/cli-policy.json` declares this system immutable and DMS
  refuses them outright. The file's `blocked_commands` *replaces* upstream's default list rather
  than extending it, so it repeats upstream's entries. (`dms update` already stops at
  "Unsupported distribution: nixos"; the policy makes that the intended answer.) The settings
  window's software-update page knows about Nix installs and stays out of the way on its own.
- **Its Hyprland integrations** — the scratchpad, tiling-layout, focus-follows-mouse and
  window-rule settings write Lua fragments under `~/.config/hypr/dms/`. This repo's `hyprland.lua`
  includes none of them, so they are inert here, and Hyprland is configured in Nix.
- **Its display settings panel** — `hyprdynamicmonitors` owns monitor profiles here.
- **Its icon-theme picker** — `icon-theme` is declared statically as `Papirus` in the `defaults`
  module, and a runtime write would be reset on the next activation. Same failure mode as the two
  dconf keys in [`theme.md`](./theme.md).
- **`input` group membership** for the evdev warning in `dms doctor`: it buys a caps-lock indicator
  and costs read access to every input device for anything running as this user.

## Startup

The unit is reordered in `modules/nixos/dms`: the packaged one is
`After=graphical-session.target` *and* `Requisite=` it, and uwsm only reaches that target once
Hyprland signals readiness — 1.4s after its first frame here. Clearing the ordering alone changes
nothing, because `Requisite=` fails the start outright; both have to go, and an `ExecStartPre`
waits for the Wayland socket instead.

Nothing raises the lock on shell start: `lockAtStartup` is off. It fires from `Lock.qml`'s
`Component.onCompleted`, i.e. on *every* shell start — including the restart
`systemd.restartIfChanged` performs during a `nixos-rebuild switch`, which locked the session out
from under whoever ran it. With the greeter authenticating before the session exists, there is
nothing for it to guard anyway.

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
