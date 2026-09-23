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
come from nixpkgs here. The package is taken from `unstable` (1.6.2) because 26.05 is a release
behind (1.4.6); `quickshell` comes from stable, which satisfies DMS's ">= 0.3.0".

One `overrideAttrs` sits on top, carrying two patches to the lock screen's fingerprint path — a
`timeout=` on the bundled PAM stack and a lower cap on the retry backoff — for the reason in
[the duty-cycle note below](#the-fingerprint-reader-was-dead-half-the-time). Both use
`--replace-fail`, so an upstream change to either anchor is a build error rather than a silent
no-op. Nothing else about the package is patched.

**Both patches run in `preBuild`, against the source tree, and then re-run `make sync-shell`.** As
of 1.6.x the QML shell is no longer installed as files: nixpkgs builds with upstream's `withshell`
tag, and `sync-shell` copies `quickshell/` into `core/internal/shellembed/dist` to be `go:embed`ed
into the `dms` binary. `$out/share/quickshell` does not exist any more, so the `postInstall`
substitutions these started life as had nothing to bite on — which is exactly how the 1.5.3 → 1.6.2
bump announced itself, as `substitute(): ERROR: file ... does not exist`. Re-running `sync-shell` is
safe (it is an `rm -rf` plus a fresh copy) and is what keeps the edits honest: it recomputes the
`.dankrev` content hash that names the directory the shell extracts itself into at runtime
(`$XDG_RUNTIME_DIR/dms-shell/<dankrev>/`). Editing the embed dir in place would leave that hash
stale and let a previously-extracted copy win. The re-run needs a `chmod -R u+w` first, because
nixpkgs' own `sync-shell` has already left a copy carrying the store's read-only permissions.

`dgop` (system monitoring), `matugen` (theming) and `khal` (calendar) are pulled in by the module's
feature toggles. `enableCalendarEvents` is off — no khal here.

## settings.json is declarative, session.json is not

`settings.json` is a store symlink, so DMS cannot write it. That is a supported mode: the shell
detects the read-only file, keeps a GUI change live for the session, and the settings modal grows a
**copy settings.json** button that puts the full JSON on the clipboard to be folded back into the
module. Mostly only the keys that differ from upstream defaults are declared — the file has ~540 of
them — with a handful pinned at their default on purpose (`lockAtStartup`,
`lockPamExternallyManaged`, `lockPamInlineFprint`, `runUserMatugenTemplates`, the two suspend
timeouts), because each is load-bearing enough that a default flip upstream should not be silent.

Because a GUI change is live-only, it is lost at the next shell restart — which every rebuild that
touches `settings.json` performs, via the `onChange` hook below. To find what has drifted before
that happens, diff the running shell against the file: `dms ipc settings dump` prints every key the
shell holds, and upstream's defaults are the `def` fields in
`Common/settings/SettingsSpec.js` — which, since the shell is embedded in the binary rather than
installed, is read from the extracted copy under `$XDG_RUNTIME_DIR/dms-shell/<dankrev>/` (or from
upstream's source tree) rather than from the package. Two caveats when reading that
diff — a `property color` is dumped as a QColor object rather than the `"#rrggbb"` string it
defaults to, so those always look changed; and `barConfigs` is rebuilt by the bar settings tab from
only the fields that tab edits, so a dumped copy comes back with keys *missing*. Declare
`barConfigs` from upstream's default with your overrides applied, never by pasting the dump.

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

A change to the declared settings does not reach a running shell on its own. DMS watches
`settings.json` (`watchChanges` on its FileView), but home-manager replaces the *symlink* rather
than the file, so the inode being watched never changes and no inotify event fires. The file entry
therefore carries an `onChange` hook that runs `systemctl --user try-restart dms.service` — safe
only because nothing locks the screen on shell start (see below).

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
belongs to the derivation's own inputs, and the source tree is not an input of the `settings.json`
derivation. The rendered file ends up with **no references at all**, so the next garbage collection
deletes the `-source` path out from under a config that is still live, leaving a dangling pointer.

Interpolating instead copies the JSON into the store as
`/nix/store/<hash>-solarized-osaka-night.json` and registers it, which is what makes GC respect it.
Verify with:

```bash
nix-store -q --references "$(readlink -f ~/.config/DankMaterialShell/settings.json)"
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

Symptom: fingerprint unlock "works sometimes". `fingerprint-status -v` says the window is wide
open, the journal shows no polkit denial, and yet touching the sensor often does nothing at all.

It is not the policy. It is a duty cycle, and the log reads it out plainly — one lock cycle, a
`Starting pam session ... with config "fprint"` every 60 seconds and a `Verification timed out`
exactly 30 seconds after each:

```bash
journalctl -b -S "-2h" | grep -E 'Starting pam session|timed out|Failed to match|Screen lock active'
```

Three upstream behaviours compose into it:

1. `assets/pam/fprint` passes no `timeout=`, so **pam_fprintd gives up on a verify after its
   default 30 seconds** and returns `PAM_AUTHINFO_UNAVAIL`.
2. DMS classifies that as `PamResult.Error` — not "nobody touched it" — and re-arms on an
   exponential backoff, `Math.min(1500 * 2^(errorTries - 1), 30000)` (`Modules/Lock/Pam.qml`).
3. `errorTries` is reset only by `checkAvail()`, which runs when the lock **opens** and on a
   settings change. Nothing resets it on wake, on activity, or on a keypress.

So roughly two minutes into any lock the backoff saturates at its 30-second cap and stays there:
the sensor is armed 30s, then unclaimed 30s, indefinitely. Walk up to the machine and it is a coin
flip whether anything is listening. Nothing on screen distinguishes the two halves — the
fingerprint icon is lit either way (see [`login-flow.md`](./login-flow.md#what-the-lock-screen-shows)).

The `overrideAttrs` in `modules/nixos/dms` patches both halves: `timeout=600` on the PAM stack, and
the backoff cap lowered from 30000 to 3000 ms.

`timeout=600` is the load-bearing one, because it removes the *error* rather than the response to
one. pam_fprintd restarts the timer after each no-match, so with `max-tries=5` one context can live
up to 50 minutes. The cap then closes the gaps between contexts, and the sequence becomes 1.5s, 3s,
3s, … between ten-minute armed windows.

| | armed | gap (saturated) | duty | 200-retry budget |
| --- | --- | --- | --- | --- |
| upstream | 30s | 30s | 50% | 3.3h |
| `timeout=600` only | 600s | 30s | 95% | 35h |
| 3s cap only | 30s | 3s | 91% | **1.8h** |
| both (here) | 600s | 3s | 99.5% | 33.5h |

**The cap is only safe alongside the long timeout.** DMS allows 200 retries per lock cycle
(`errorTries < 200`, `Pam.qml`), and at upstream's 30-second timeout a 3-second cap spends all 200
in under two hours — a laptop locked over lunch would come back with the reader switched off
entirely. At 600s per attempt the same budget covers ~33 hours, past the point
`dedsm.fingerprintPolicy.maxTimeSinceUnlock` demands a password anyway.

The budget does burn faster in the cases that fail **instantly** — a gate denial, a missing reader,
or an fprintd wedged by a suspend
([`login-flow.md`](./login-flow.md#when-it-is-not-the-policy-fprintd-wedged-by-a-suspend)) — where
200 retries take ~10 minutes rather than ~1.7 hours. Nothing is lost by giving up sooner there:
within a lock cycle a denial is monotonic. Both clocks only move forward, and the failure counter
is cleared only by a password authentication, which ends the lock. There is no state to wait for.
The wedge is the one that could have outlasted the budget, and does not: it is repaired at the
moment of resume, before the lock screen is looked at.

Two things belong on the record:

- **The gate tail.** polkit is consulted on `VerifyStart`, so an attempt armed just before a policy
  window lapses stays usable until it ends — at most ten minutes, on windows of 48 and 156 hours.
  This is also why the stack does *not* use `timeout=-1`, which `pam_fprintd(8)` documents as
  "always active while this module is loaded" and which otherwise fits exactly: with no timeout
  there is never a second `VerifyStart`, so on an untouched machine the gate would be consulted
  once at lock time and never again.
- **The QML anchor is the fragile half.** `assets/pam/fprint` is six lines and nixpkgs already
  patches it; the cap is anchored to an arithmetic expression inside a 560-line QML file upstream
  refactors freely. `--replace-fail` makes that a build failure rather than a silent no-op, which
  is the intended outcome — re-derive the expression and move on. The *paths* are the other moving
  part: they follow upstream's build layout, which is why 1.6.x's move to an embedded shell turned
  both into `preBuild` edits (see [Packaging](#packaging)).

Neither knob addresses the actual defect, which is upstream's: a timeout with **nobody present** is
not an error, and `Pam.qml:298` counts it as one. The principled fix is to record when a context
started and reset `errorTries` in the `Error` branch when it lived long enough to have been a
genuine timeout. That is a multi-line change and belongs upstream, not in a `substituteInPlace`.

A no-match is a different thing and is not a bug: `Failed to match fingerprint` in the log means
the sensor *did* read a finger and rejected it, and it counts against both `maxFprintTries` and the
policy's `failureLimit`.

### What it costs in power

Holding a verify open pins the reader out of USB runtime suspend — measured at 63.9s active out of
64s wall during a claim, against `control=auto` and a 2s autosuspend delay otherwise. The draw
itself is **below what this machine can resolve**: system noise over a two-minute run is ~640 mW
with ~1 W of drift between baselines, so the delta comes out as noise. The real bound is the USB
descriptor — `bMaxPower = 100mA` on a 5 V bus, so **500 mW, ceiling**. Ten minutes at that ceiling
is 83 mWh against a ~48 Wh pack (`charge_full` 3.119 Ah at 15.39 V), or 0.17%; the change's actual
delta is the extra ~45% of lock time, ≈0.47%/hour worst case and realistically far less. It is zero
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
| `CTRL+ALT+L` | `loginctl lock-session` (unchanged — DMS listens on logind) |
| `CTRL+ALT+SHIFT+L` | `systemctl --user restart dms.service`, the locked-session escape hatch |

`dms ipc` with no arguments lists every target; the live surface is wider than upstream's
`docs/IPC.md`.

Mind the arity. `brightness increment` documents its device as optional but the running signature is
`increment(step: string, device: string)`, so the bind passes `""` (the default backlight) — with
one argument it fails, and a bind's `exec_cmd` failure goes nowhere, so the key simply does nothing.
`audio increment/decrement` really does take only the step; everything else above is a
zero-argument toggle.

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
