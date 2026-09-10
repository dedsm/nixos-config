# Login & lock flow (manwe)

How boot gets to a usable session, and what guards it. LUKS is the at-rest
security boundary; the greeter authenticates before a session exists.

## Boot path

1. **LUKS passphrase** in the systemd initrd — the real security boundary,
   prompted by plymouth (`boot.plymouth.enable` in `modules/nixos/core`, with
   `quiet` and `consoleLogLevel = 0`). The splash then holds the display until
   the greeter draws: greetd is aliased to `display-manager.service` and
   ordered `After=plymouth-quit-wait.service` by its NixOS module, so nothing
   console-shaped appears between the initrd and the login prompt.
   `services.greetd.greeterManagesPlymouth` would remove even the black frame
   between them, but it needs a greeter that quits plymouth itself and
   dank-greeter has no plymouth support.
2. **The DMS greeter**: greetd's `default_session` is `dms-greeter`, running as
   its own system user in a short-lived Hyprland instance
   (`services.displayManager.dms-greeter`). It reads david's DMS config, so the
   login screen carries the same theme and wallpaper as the desktop behind it.
3. **The session**: on a successful password the greeter hands over to
   `uwsm start hyprland-uwsm.desktop`, and DankMaterialShell starts unlocked —
   the authentication already happened.

### Why not autologin plus a boot lock

The previous arrangement autologged in and had the lock screen guard the boot,
which reached a prompt marginally sooner. It was abandoned because of what the
eye actually sees: greetd handed the console to the session, so VT text
appeared, then Hyprland, then the desktop painted, and only then — once the
shell had loaded and could raise its own lock surface — the lock. DMS *is* the
locker, so no configuration makes that lock appear before the shell exists;
measured on this machine the desktop was visible for about 1.15s.

Authenticating first removes the problem rather than shortening it: compositor
to compositor, with nothing unlocked in between. It also puts the password back
on the login stack, which is the ordinary place to unlock the login keyring.

## Fingerprint policy: one gate, in front of fprintd

The conditions Apple documents for Touch ID, implemented here. Apple's
[Platform Security guide][apple] requires the password when the Mac was just
restarted, when the user logged out, after 48 hours with no unlock at all,
after 156 hours with no password *and* 4 hours with no biometric unlock, on a
remote lock, or after five failed matches.

[apple]: https://support.apple.com/guide/security/optic-face-touch-passcodes-passwords-sec9479035f1/web

| Apple's condition | Here |
| --- | --- |
| Just turned on or restarted | State lives in `/run`; after a boot there is none |
| Logged out | `pam_exec` on greetd's session *close* drops the state |
| Not unlocked for 48 h | `maxTimeSinceUnlock`, against the newer of the two clocks |
| No password for 156 h **and** no biometric for 4 h | `maxTimeSincePassword` / `fingerprintGrace` |
| Five failed matches | `failureLimit`, counted across locker instances |
| Remote lock | No analogue on this machine |

manwe keeps Apple's numbers unmodified — the module defaults. The shape is the
interesting part: the 4-hour grace only applies once the 156-hour password
interval has lapsed, and from then on the reader keeps working *as long as you
keep using it* — each fingerprint unlock buys another 4 — until a longer gap,
or 48 hours with the machine untouched, at which point only a password will do
(and typing it restarts the 156 hours). Set `fingerprintGrace = 0` to turn the
password interval into a hard cap.

manwe briefly ran a 10-hour password interval. It was dropped because a
workday exhausts 10 hours, so the overnight gap then always exceeded the
4-hour grace: in practice, a password at every first unlock of the morning,
where a Mac asks roughly once a week.

Enforcement is `modules/nixos/fingerprint-policy/`
(`dedsm.fingerprintPolicy`), in **one** place for the whole machine: a polkit
rule on fprintd's `net.reactivated.fprint.device.verify`. Everything that can
use the reader goes through fprintd — the lock screen via `pam_fprintd`, `sudo` and
`login` via `pam_fprintd` — so nothing needs to opt in, and nothing can opt
out.

State lives in `/run/fingerprint-policy/`:

- `password-auth` — mtime of the last password authentication, written by
  `pam_exec` from the auth stacks named in `passwordServices` (dankshell, sudo,
  login, greetd). `/run` is a tmpfs, so "no file" and "nothing since boot" are
  the same thing: the restart condition needs no code and cannot be forgotten.
- `fingerprint-unlock` — mtime of the last successful match, written by the
  monitor below. Any match counts, including a `sudo` one; that is the
  permissive reading of "the fingerprint unlocked it".
- `failures` — consecutive failed matches.

A stamp dated in the *future* (a backwards clock step) is treated as no stamp
at all — elapsed time is not something to hand a security decision to when the
clock has just moved.

One window for the machine, not one per user, on purpose: the polkit subject
is the *calling process*, and `pam_fprintd` runs inside `sudo`, which is root.
A per-user window would look for root's stamp on a sudo fingerprint while
sudo's own PAM stack had written david's.

`fingerprint-status` (`-v` to also report the open case, with the tightest
clock) prints why a password is being asked for. It has to be run by hand now —
the lock screen used to render it in a `cmd[]` label, which DMS has no
equivalent for (see below).

### Logout, and greetd's two sessions

The logout condition is `pam_exec` on the session stack of whatever opens the
desktop — `sessionServices`, which is just `greetd`. Two details make that
less obvious than it sounds:

- **The login password now refreshes the clock.** greetd is in
  `passwordServices`, and the greeter authenticates through it, so the stamp is
  written at login. The policy's "password after a restart" condition is
  therefore satisfied by the login itself, and fingerprint is available for the
  first lock of the session — which is exactly Apple's behaviour, and one thing
  the autologin design could not do (its `initial_session` went through
  `start_unauthenticated_session(…, authenticate: false)`, so no password ever
  reached PAM and the first *lock* had to be the password one).
- **The greeter runs through the same PAM service as the session.** greetd
  takes a `greeter_service` and a `pam_service`, and here both are `greetd`
  (there is no `/etc/pam.d/greeter`, and `other` denies sessions — the greeter
  could not start otherwise). So the greeter's *own* session closing lands in
  this hook too, moments after the password typed into it refreshed the clock,
  and would wipe it. The hook therefore fires only for a user listed in
  `users`; `dms-greeter` is not one.

### Who may write the state

`pam_exec` runs with the privileges of whatever is running the PAM
conversation, and that is not always root: **the lock screen is an ordinary
user process running its own PAM conversation** — the most important one here. So the
state directory is setgid `fingerprint-policy`, mode 2775, and
`dedsm.fingerprintPolicy.users` puts the locker's user in that group. Miss
that and the unlock silently cannot refresh the clock, and the reader stays
off (`fingerprint-status` says which).

Which means code running as that user could forge a stamp. That is inherent
rather than a shortcut — the unlock signal originates *inside* a process that
user controls — and it buys nothing against the attacker this policy is for:
someone holding a locked laptop, with no code running as its owner. Anything
already running as david can read the keystrokes of the password instead.

### Why the gate is at fprintd and not in PAM

The lock screen runs fingerprint in a *second, parallel* PAM context off DMS's
own bundled stack, so that the sensor and the password field are live at the
same time (`settings.lockPamInlineFprint = false`). Whatever ends up in
`/etc/pam.d/dankshell` therefore governs the password path only.

Getting DMS to use that file needs `settings.lockPamExternallyManaged` left
**off**, which reads backwards. That setting does not mean "the admin declares
the stack"; it makes DMS authenticate against `/etc/pam.d/login`, which here is
password-only by design, *and* it suppresses the parallel fingerprint context.
Turned on, it disables fingerprint unlock twice over. Left off, DMS picks
`/etc/pam.d/dankshell` simply because the file exists. And that path
only ever calls `pam_authenticate` — no session phase, which also rules out
`pam_timestamp`, the module that otherwise looks purpose-built for this (it
creates its timestamp in `pam_sm_open_session`). hyprlock, which this replaced,
did not use `pam_fprintd` at all: it drove fprintd over D-Bus directly. Either
way the policy cannot live in PAM.

fprintd, by contrast, checks polkit on *every* invocation of a method that
needs a permission, and caches nothing for a `NO`. `VerifyStart` needs
`verify`, and the locker re-issues `VerifyStart` after each failed match and on
every resume.
So the window is re-evaluated at exactly the moments that matter, **without
restarting the locker**: a locker that has been up since before the window
lapsed simply stops accepting fingerprints.

Three things that are easy to get wrong here:

- **`enroll` has to be denied alongside `verify`.** Not because enrolling
  matters at the lock screen: `Claim` requires `verify` *or* `enroll`, and
  fprintd's check returns on the first permission that authorizes. Deny only
  `verify` and a locker's `Claim` falls through to `enroll`, whose default is
  `auth_self_keep` — and fprintd passes `ALLOW_USER_INTERACTION`, so that pops
  an agent dialog (there is one running: `polkit-gnome`) *underneath* the lock
  screen.
- **The rule must fail closed.** If the spawned helper throws, the rule aborts
  and the next one applies — which is fprintd's own `allow_active=yes`. The
  `try`/`catch` returning `NO` is the only thing between a broken helper and
  fingerprint auth silently coming back. Same reasoning for a counter file
  that exists but does not parse.
- **`polkit.spawn` blocks polkitd** while it runs (10s cap, runs as the
  unprivileged `polkitd` user). The helper is three `stat`-shaped commands and
  the state files are world-readable for exactly that reason. Do not grow it.

### What the lock screen shows

Not much, and this is the one place the DMS lock is worse than what it
replaced. When the gate says no, `pam_fprintd` fails; DMS treats that as a
retryable error and quietly re-arms (up to 200 times) while the password field
stays live and working. Verified on hardware: no hang, no spin visible, the
password path is unaffected — but the fingerprint icon stays lit as though the
sensor were usable, and nothing on screen says why it is not.

hyprlock could not tell either, which is why its config carried a second label
running `cmd[update:5000] fingerprint-status` to fill the slot with *why* — "no
unlock since boot", "window lapsed", "too many failed attempts". DMS has no
equivalent: every lock-screen setting is a show/hide toggle, a font or a
wallpaper, with no custom label or command. `fingerprint-status` is still
installed; it just has to be run from a terminal now.

### The match monitor, and why it is a listener

polkit only ever sees an attempt *start*; whether it matched is reported by
fprintd to its client. Counting `VerifyStart` calls instead would be wrong —
a resume issues one without anyone having touched anything. And both the
counter *and* the 4-hour grace need to know that a match happened.

So `fingerprint-failure-monitor.service` watches fprintd's `VerifyStatus`
signal on the system bus: `verify-no-match` bumps the counter,
`verify-match` clears it and stamps `fingerprint-unlock` (a password auth
clears the counter too). fprintd broadcasts that signal
and its D-Bus policy does not restrict who may receive it, so this needs no
monitor privileges — `gdbus monitor` and a `case` statement. `stdbuf -oL`
matters: without it glib's stdio sits on the lines in the pipe.

If the monitor dies, the counter stops moving and the time window still
applies — it fails open, deliberately, because the alternative is a service
crash locking you out of your own reader.

This is what makes the limit stick. The locker's own cap is per instance —
DMS's `maxFprintTries` is set to 5 in `modules/common/users/common/dms/` to
match, but `CTRL+ALT+SHIFT+L` (below) restarts the shell on a locked session and
that resets it. The counter in `/run` is what a restart does not reset.

### `misc:allow_session_lock_restore`

Under `ext-session-lock` the compositor keeps the session locked when a locker
dies without unlocking — that is the protocol's whole point. Hyprland tracks
that as a protocol-level locked flag which **outlives the locker process**,
and by default *denies* any subsequent lock client while it is set
(`Cannot re-lock, misc:allow_session_lock_restore is disabled`; the client
logs `Seems we got yeeten`). A locked session whose locker is gone is then a
dead end: no lock surface to type into, no unlock path, every keybind filtered
out. Reboot only.

`misc:allow_session_lock_restore = true` (hyprland module) lets a new locker
take over the lock instead, which makes **`CTRL+ALT+SHIFT+L`** a real escape
hatch: bound with Hyprland's `locked` flag so it runs while locked, it restarts
`dms.service`, and the fresh shell takes the orphaned lock. A locker crash is
recoverable in place rather than by power-cycling.

The trade-off is that a lock screen can be *replaced* rather than only
*added*, so a hostile client could swap in a fake prompt. That requires access
to the Wayland socket, i.e. already running code as this user, which is past
the boundary the lock defends — whereas the failure it prevents is a crashed
locker bricking the session until it is power-cycled.

This used to carry more weight than it does now. The sleep hook once had to
*kill* a running locker and start a password-only one in its place, and getting
that sequence wrong (or overlapping it) landed exactly in the dead end above.
The fprintd gate removed the need to replace anything — a locker that was up
before the window lapsed stops accepting fingerprints without being restarted,
because the gate is re-checked on the `VerifyStart` that follows every resume.
Locking before suspend is now just `settings.lockBeforeSuspend`, inside the
shell that already owns the lock.

## Idle, DPMS, and the black-screen backstops

DMS's `IdleService` drives both timers off `ext_idle_notifier_v1`, configured in
`modules/common/users/common/dms/`: **`acLockTimeout` / `batteryLockTimeout` =
300s → lock**, **`acMonitorTimeout` / `batteryMonitorTimeout` = 600s → monitors
off**. Suspend is left to logind (`acSuspendTimeout = 0`; see
[`hibernation.md`](./hibernation.md)). Nothing else in the repo writes DPMS.
These are the timings hypridle used, which DMS replaced.

The incident below predates DMS and belongs to hypridle, but the backstop it
produced is the reason the compositor-level guard exists — and that guard is
what makes any single idle daemon, this one included, non-load-bearing.

hypridle recreated *every* listener's idle notification whenever a dbus inhibit
was taken or released — Firefox does this each time audio starts and stops. That
reset the timers **and** cleared each listener's internal "idled" flag. If the
DPMS listener had already fired, the panels stayed physically off while hypridle
believed they were on, so on resume it fired no `on-resume` for that listener
and nothing turned them back on.

That is a real incident, not a hypothetical (2026-07-31): DPMS off at 18:36, a
Firefox audio inhibit released at 18:55:58 re-armed both listeners, and the
resume at 19:01 restored nothing. The session was fully alive underneath — the
fingerprint reader even reported `verify-match` — but the screens were dark and
the machine looked hung. Only replugging the dock (forcing output
re-enumeration) brought the picture back.

The guard that survived the migration is the compositor-level one:
**`misc.mouse_move_enables_dpms` / `misc.key_press_enables_dpms`** in
`modules/common/users/common/hyprland/`. Both default to **false**, which is
what made the state unrecoverable from the keyboard. These make Hyprland wake
the display on input regardless of what any idle daemon thinks — and it is the
only guard that survives that daemon being wrong, wedged, or dead. DMS's own
`IdleService` turns monitors back on from any resume (`requestMonitorOn`), which
covers the same ground as hypridle's per-listener `on-resume` did, but do not
rely on it alone.

If a black screen ever recurs, the machine is probably fine — check
`journalctl --user -u dms` around the resume before concluding the GPU hung, and
confirm with a clean `grep -i amdgpu` (a real hang shows ring timeouts / GPU
reset, not just `DMUB HPD IRQ` dock events).

## Keyring unlock (gnome-keyring)

The greeter authenticates with a password on greetd's own PAM stack, which is
the ordinary place to unlock the login keyring:
`security.pam.services.greetd.enableGnomeKeyring = true` in
`modules/nixos/greetd` runs both the auth handler (which forwards the typed
password) and the session handler (`auto_start`).

`modules/nixos/dms` sets the same option on the `dankshell` service, so the
lock screen can also unlock the keyring — relevant after a session where the
daemon was relocked, and the reason a fingerprint unlock cannot do it: it
carries no secret to forward. Under the previous autologin design this was the
*only* path, since no password reached PAM at login at all.

Constraint: the login keyring's password must equal the user password (fix
with seahorse if they ever diverge).

KWallet was dropped entirely (2026-07): kwalletd had been dead weight since
gnome-keyring took over `org.freedesktop.secrets`, its PAM module structurally
cannot be unlocked from a screen locker (auth phase only stashes; the unlock
lives in the session phase, which lockers never run), and everything in the
old wallet file had already been re-created in gnome-keyring.

## Rebuilds and the uwsm session units — carried patch

`nixos-rebuild switch` restarts *user* units whose definition changed, and
uwsm's session units are booby-trapped for that. `wayland-session-bindpid@.service`
exists solely to translate "the thing I was watching went away" into "tear down
the graphical session" (`OnSuccess=wayland-session-shutdown.target`,
`OnSuccessJobMode=replace-irreversibly`). So a rebuild that merely *rebuilds
uwsm* — any flake input bump that touches its closure — stops that unit, and
uwsm dutifully SIGKILLs the whole session: Hyprland, every `app-Hyprland-*.scope`,
your terminals, and the `nixos-rebuild` process itself, which dies mid-switch and
leaves the system half-activated.

Not hypothetical: it happened on 2026-06-23, 07-21, 07-30 and 08-08, always with
the same signature ~2s after `switching to system configuration`:

```
systemd[1]:    Reexecution requested from client PID … ('.switch-to-conf')
systemd[USER]: Stopping Bind graphical session to PID …
systemd[USER]: wayland-session-bindpid@…: Triggering OnSuccess= dependencies.
systemd[USER]: app-Hyprland-foot-….scope: Killing process … (.nixos-rebuild-) with signal SIGKILL
```

Upstream fixed this in [nixpkgs#532275](https://github.com/NixOS/nixpkgs/pull/532275)
(merged to master 2026-06-16, merge commit `a75cd823`) by setting
`restartIfChanged = false` on `wayland-wm@` and `wayland-session-bindpid@` — the
same treatment `niri.nix` and the display-manager modules already had. It was
**not** backported to release-26.05, so `modules/nixos/hyprland/` carries it
locally. `enableDefaultPath = false` goes with it: without it the generated
drop-in would carry NixOS' default `PATH=`, clobbering the PATH uwsm imported
into the user manager and breaking `uwsm app` spawns.

The patch expires by itself. Three assertions in that module fail the build when
the pinned nixpkgs starts setting `restartIfChanged` on those units (delete the
local block and this section), when uwsm's module moves upstream, or when the
pin advances past the recheck date. The clock is `nixpkgs.lastModified`, not
wall time — deliberately, since the bug can only bite on a rebuild that advances
the pin, and pure eval has no wall clock anyway.

Verify the drop-in survives any refactor here — `X-RestartIfChanged` is read
from the `[Service]` section, not `[Unit]`:

```bash
cat result/etc/systemd/user/wayland-session-bindpid@.service.d/overrides.conf
```

## Boot-speed rationale

Two systemd interactions used to delay the login prompt and are worked around
here — keep them in mind before adding boot-time oneshots:

- greetd's stock unit is `Type=idle`, which delays exec until the boot job
  queue drains (capped ~5s). The greetd module forces `Type=exec`.
- `powertop --auto-tune` (laptop module) takes ~6s; it now runs from a
  systemd timer (`OnBootSec=30s`) instead of inside the boot transaction.

The remaining pre-prompt time is firmware, the LUKS KDF, and ~3s of userspace
bring-up. If a future change makes the prompt slow again, compare
`journalctl -b -o short-monotonic` timestamps (greeter PAM session open vs.
`Started greetd.service`) rather than trusting `systemd-analyze critical-chain`,
which hides both effects.
