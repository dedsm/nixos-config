# Login & lock flow (manwe)

How boot gets to a usable session, and what guards it. The design goal: reach
an authentication prompt as fast as possible after the LUKS passphrase, with
LUKS as the at-rest security boundary and hyprlock as the session gate.

## Boot path

1. **LUKS passphrase** in the systemd initrd — the real security boundary.
2. **greetd autologin**: `dedsm.greetd.autologinUser` (set to `david` for
   manwe in `flake.nix`) adds a greetd `initial_session` that starts
   `uwsm start hyprland-uwsm.desktop` directly — no greeter, no password.
   tuigreet remains the `default_session`, so after a logout (or if the boot
   lock fails to start) you get the normal greeter.
3. **hyprlock as the gate**: Hyprland's autostart launches hyprlock *first*,
   before any other autostart. It is password-only without being told to: the
   fingerprint window lives in `/run` and nothing has opened it yet this boot
   (see below). If hyprlock exits non-zero within 5 seconds it failed to
   start, and the session is torn down (`uwsm stop`) so greetd falls back to
   tuigreet instead of leaving the session exposed.

Because the session is only ever visible after hyprlock authentication, the
autologin does not weaken interactive security; at-rest security is LUKS
either way.

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

manwe keeps Apple's numbers except the password interval, which is **10 hours**
rather than 156. The rest of the shape is theirs, and the shape is the
interesting part: past that 10 hours the reader keeps working *as long as you
keep using it* — each fingerprint unlock buys another 4 — until 48 hours pass
with the machine untouched, at which point only a password will do. Set
`fingerprintGrace = 0` to turn the password interval back into a hard cap.

Enforcement is `modules/nixos/fingerprint-policy/`
(`dedsm.fingerprintPolicy`), in **one** place for the whole machine: a polkit
rule on fprintd's `net.reactivated.fprint.device.verify`. Everything that can
use the reader goes through fprintd — hyprlock over D-Bus directly, `sudo` and
`login` via `pam_fprintd` — so nothing needs to opt in, and nothing can opt
out.

State lives in `/run/fingerprint-policy/`:

- `password-auth` — mtime of the last password authentication, written by
  `pam_exec` from the auth stacks named in `passwordServices` (hyprlock, sudo,
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
clock) prints why a password is being asked for; the lock screen runs it in a
`cmd[]` label, because hyprlock itself cannot tell (see below).

### Logout, and greetd's two sessions

The logout condition is `pam_exec` on the session stack of whatever opens the
desktop — `sessionServices`, which is just `greetd`. Two details make that
less obvious than it sounds:

- **Autologin never traverses the auth stack.** greetd's `initial_session`
  goes through `start_unauthenticated_session(SessionClass::User, …)` with
  `authenticate: false`, so no password flows and no stamp is written at boot.
  That is what makes the boot lock password-only without anything having to
  ask for it — and it also means the auth-stack rewrite above cannot affect
  the autologin path at all.
- **The greeter runs through the same PAM service as the session.** greetd
  takes a `greeter_service` and a `pam_service`, and here both are `greetd`
  (there is no `/etc/pam.d/greeter`, and `other` denies sessions — tuigreet
  could not start otherwise). So tuigreet's *own* session closing lands in
  this hook too, moments after the password typed into it refreshed the clock,
  and would wipe it. The hook therefore fires only for a user listed in
  `users`; `greeter` is not one.

### Who may write the state

`pam_exec` runs with the privileges of whatever is running the PAM
conversation, and that is not always root: **hyprlock is an ordinary user
process running its own PAM stack** — the most important one here. So the
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

hyprlock does not use `pam_fprintd`. It drives fprintd over D-Bus itself and
only ever calls `pam_authenticate` for the password path — no session phase,
which also rules out `pam_timestamp`, the module that otherwise looks
purpose-built for this (it creates its timestamp in `pam_sm_open_session`).
Any policy written into `/etc/pam.d/hyprlock` is invisible to the fingerprint
path.

fprintd, by contrast, checks polkit on *every* invocation of a method that
needs a permission, and caches nothing for a `NO`. `VerifyStart` needs
`verify`, and hyprlock re-issues `VerifyStart` on logind's
`PrepareForSleep(false)` — i.e. on every resume — and after each failed match.
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

hyprlock has no idea any of this exists. A denied `Claim`/`VerifyStart` only
logs `WARN fprint: could not claim device` and returns — it does not fail the
prompt, clear a password being typed, or say anything on screen. The one
visible effect is that `$FPRINTPROMPT` never gets set, so the "touch the
sensor" line is simply absent.

That is correct but silent, so the hyprlock config carries a second label
running `cmd[update:5000] fingerprint-status`, which fills the same slot with
*why* — "no unlock since boot", "window lapsed", "too many failed attempts" —
and prints nothing at all when the reader is available.

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

This is what makes the limit stick. hyprlock caps itself at 3 failed matches,
but only per locker instance, and `CTRL+ALT+SHIFT+L` (below) spawns a fresh
one on a locked session. The counter is what a respawn does not reset.

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
hatch: bound with Hyprland's `locked` flag so it runs while locked, it spawns
a fresh locker, so a locker crash is recoverable in place rather than by
power-cycling.

The trade-off is that a lock screen can be *replaced* rather than only
*added*, so a hostile client could swap in a fake prompt. That requires access
to the Wayland socket, i.e. already running code as this user, which is past
the boundary hyprlock defends — whereas the failure it prevents is a crashed
locker bricking the session until it is power-cycled.

This used to carry more weight than it does now: the sleep hook had to *kill*
a running locker and start a password-only one in its place, and getting that
sequence wrong (or overlapping it) landed exactly in the dead end above. The
fprintd gate removed the need to replace anything, so
`hypridle`'s `before_sleep_cmd` is now only "start a locker if none is
running", and it holds the sleep inhibitor until that locker is up.

## Idle, DPMS, and the black-screen backstops

`modules/common/users/common/wayland/hypridle/` drives two idle listeners off
`ext_idle_notifier_v1`: **300s → `loginctl lock-session`**, **600s → DPMS off**.
Nothing else in the repo writes DPMS.

Both listeners turn the display back on when you resume, which looks redundant
and is not. hypridle recreates *every* listener's idle notification whenever a
dbus inhibit is taken or released — Firefox does this each time audio starts and
stops. That resets the timers **and** clears each listener's internal "idled"
flag. If the DPMS listener had already fired, the panels stay physically off
while hypridle believes they are on, so on resume it fires no `on-resume` for
that listener and nothing turns them back on.

That is a real incident, not a hypothetical (2026-07-31): DPMS off at 18:36, a
Firefox audio inhibit released at 18:55:58 re-armed both listeners, and the
resume at 19:01 restored nothing. The session was fully alive underneath — the
fingerprint reader even reported `verify-match` — but the screens were dark and
the machine looked hung. Only replugging the dock (forcing output
re-enumeration) brought the picture back.

Two independent guards, deliberately both:

- **`on-resume = dpms "on"` on the 300s lock listener.** Idempotent, and covers
  the case above because the *lock* listener's resume did still fire.
- **`misc.mouse_move_enables_dpms` / `misc.key_press_enables_dpms`** in
  `modules/common/users/common/hyprland/`. Both default to **false**, which is
  what made the state unrecoverable from the keyboard. These make the compositor
  wake the display on input regardless of what hypridle thinks.

Keep the second one in mind before trusting any single idle daemon: it is the
only guard that survives hypridle being wrong, wedged, or dead.

If a black screen ever recurs, the machine is probably fine — check
`journalctl -b -1 | grep hypridle` for an `Idled:` with no matching `Resumed:`
for the same rule id before concluding the GPU hung, and confirm with a clean
`grep -i amdgpu` (a real hang shows ring timeouts / GPU reset, not just
`DMUB HPD IRQ` dock events).

## Keyring unlock (gnome-keyring)

With autologin no password flows through PAM at login, so the login keyring
starts locked. The greetd module sets
`security.pam.services.hyprlock.enableGnomeKeyring = true`:
pam_gnome_keyring's *auth* handler forwards the password typed at hyprlock to
the already-running daemon (hyprlock only runs PAM's auth phase — that's
sufficient for gnome-keyring). A fingerprint unlock carries no secret to
forward, which is why the keyring depends on the first unlock after boot being
a password one; the fingerprint policy above guarantees that without any
special-casing, since nothing has opened the window yet at that point.

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
