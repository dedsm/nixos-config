# Dark/light theming

The environment switches between a Solarized light and dark variant on a schedule. **Who drives
that differs per platform:**

- **Linux** — DankMaterialShell. It decides the mode (sunrise/sunset via GeoClue2), writes the
  dconf keys, and runs matugen, which renders the templates the `theme` module declares. See
  [`dms.md`](./dms.md).
- **Darwin** — `dark-notify`, driven by `AppleInterfaceStyle`, exactly as before.

The `theme` home-manager module (`modules/common/users/common/theme/default.nix`, opt-in via
`theme.enable`) holds what is shared: the Solarized palette in its `colors` attrset (also dumped to
`~/.colorscheme-palette` as JSON), the tmux theme files, the matugen templates and hooks that carry
a transition to foot and tmux, and the activation guard below. It no longer runs a scheduler of its
own on Linux — darkman is gone.

## The one rule: one owner for `color-scheme` and `gtk-theme`

Two dconf keys decide the mode for almost every GUI app on the Linux side:

```
/org/gnome/desktop/interface/color-scheme    prefer-dark | prefer-light
/org/gnome/desktop/interface/gtk-theme       adw-gtk3-dark | adw-gtk3
```

`xdg-desktop-portal-gtk` reads them and re-exports them over
`org.freedesktop.portal.Settings` / `org.freedesktop.appearance`; Firefox, Slack and every other
Electron app follow *that*, not the GTK config files. So the chain is:

```
DMS → dconf → xdg-desktop-portal-gtk → org.freedesktop.portal.Settings → Firefox / Slack / …
```

**Nothing else in this repo may declare those two keys**, whether directly via `dconf.settings` or
indirectly via home-manager options that mirror into them. Concretely, this is why
`modules/common/users/common/defaults/common/default.nix` deliberately does *not* set:

| Setting | Why it's absent |
| --- | --- |
| `dconf.settings."org/gnome/desktop/interface".color-scheme` | Pins the portal to one mode |
| `dconf.settings."org/gnome/desktop/interface".gtk-theme` | Same, for the GTK3 theme name |
| `gtk.theme.name` | home-manager mirrors it into **both** `gtk-3.0/settings.ini` *and* the `gtk-theme` dconf key |
| `gtk.gtk3.colorScheme` | Mirrors into the `color-scheme` dconf key |
| `gtk4.extraConfig.gtk-application-prefer-dark-theme` | Hard-locks GTK4/libadwaita apps to one mode in `gtk-4.0/settings.ini` |

`gtk.theme.package` is gone with `gtk.theme`. DMS points `gtk-theme` at `adw-gtk3` /
`adw-gtk3-dark` and patches a copy into `~/.local/share/themes`, so that theme has to be on disk:
`modules/nixos/dms` installs `pkgs.adw-gtk3` for exactly this reason. A missing theme is not an
error anywhere — GTK3 apps just fall back to raw defaults.

### The failure mode this prevents

Declaring any of the above makes **every home-manager activation** re-assert the light value:
`dconf load` runs on each activation, and the `dconf-cleanup` pass additionally resets keys a
generation *stopped* managing back to their schema defaults.

That write is easy to miss because it usually produces no visible flicker. `home-manager-<user>.service`
runs with no `DBUS_SESSION_BUS_ADDRESS`, so home-manager wraps `dconf load` in a throwaway
`dbus-run-session` — the write lands in `~/.config/dconf/user` but the *real* session bus never sees a
change signal, so no app repaints. What it does do is bump the dconf shm invalidation flag
(`~/.cache/dconf/user`), so each app silently picks up the light value the next time it reads the
database — typically when it next repaints.

The symptom: an afternoon `nixos-rebuild switch` on one workspace, and Firefox/Slack are found in
light mode minutes later on another, hours after the shell correctly switched them to dark. The
usual "fix" is toggling light and back to dark, which re-runs the transition.

### The activation guard

Removing the static declarations is the actual fix, but `home.activation.reassertColorScheme` in the
`theme` module makes it stick: ordered `after = ["dconfSettings"]`, it re-writes both keys to
whatever mode is current, so no activation can leave them stale. It outlived darkman deliberately —
the trigger is home-manager's own `dconf load`, not whoever owns the keys at runtime, and DMS would
otherwise only put them back at its next transition.

Two details worth knowing:

- It reads `~/.local/state/theme/mode` rather than asking DMS. `dms ipc` needs the shell's socket
  and would fail in the activation service (which has no session bus), silently reading as "light"
  — the exact bug it exists to prevent. That file is written by the `theme-mode` matugen template
  on every transition, so it is always the mode DMS last built. `home.activation.initTmuxTheme` and
  the `theme-get` script read the same file, for the same reason.
- It prefers the live user bus (`/run/user/$(id -u)/bus`) when the session is up, so the write emits a
  real `SettingChanged` and apps repaint immediately; it falls back to a throwaway `dbus-run-session`
  at boot, where landing the value in the database is all that matters.

The DAG entry is written out longhand (`{ after; before; data; }`) instead of using
`lib.hm.dag.entryAfter`, because `modules/common/default.nix` `import`s these files with the **NixOS**
`lib` — the home-manager `lib.hm` extensions are not in scope.

## Hyprland border colour

Handled by DMS: its matugen template set includes `hypr-colors.lua`, which is generated in the Lua
form this repo's Hyprland config already uses. The `theme` module used to do this itself through
`hyprctl eval`, working around two things — that darkman's scripts never inherited
`HYPRLAND_INSTANCE_SIGNATURE` from the compositor, and that `hyprctl keyword` is refused under the
non-legacy parser. Both problems left with darkman.

One deliberate loss: the old helper painted the border Solarized *blue* in dark mode and *red* in
light, as a mode indicator. The generated colours follow the palette instead. Put it back with a
user template in `~/.config/matugen/config.toml` if it is missed.

## foot and tmux

- **foot** is signalled in place: `SIGUSR1` selects `[colors-dark]`, `SIGUSR2` selects
  `[colors-light]`. Both palettes are declared in the `foot` settings in
  `modules/common/users/common/defaults/common/default.nix`; `main.initial-color-theme` pins what a
  *newly started* terminal uses before the first transition.
- **tmux** has no signal equivalent, so each transition (a) repoints
  `~/.local/state/tmux/current-theme.conf` at the combined Solarized config for the new mode, which
  is what new servers source at startup, and (b) walks every tmux socket under `/run/user/<uid>` and
  `/tmp` and `source-file`s it into the already-running servers. On Darwin the same work is done by
  `~/.local/bin/theme-apply`, invoked by the `dark-notify` launchd agent (it searches `/private/tmp`,
  because Nix's `find` does not follow the `/tmp` symlink on macOS).

### How a transition reaches them on Linux

DMS merges the `[templates]` section of `~/.config/matugen/config.toml` into the matugen config it
generates (`settings.runUserMatugenTemplates`), so anything declared there renders — and its
`post_hook` runs — on every theme change and every light/dark flip. That is what replaced darkman's
transition scripts. The `theme` module declares two templates, and neither takes its colours from
matugen: this palette is Solarized, and only the *mode* moves. `input_path_modes` picks the input
file for the scheme matugen just built, which is why no hook has to work out which mode it is in.

| Template | Output | `post_hook` |
| --- | --- | --- |
| `theme-mode` | `~/.local/state/theme/mode` (the word `dark` or `light`) | signals foot `SIGUSR1`/`SIGUSR2` |
| `tmux` | `~/.local/state/tmux/current-theme.conf` | `source-file`s it into every live tmux socket |

DMS ships its own `foot.ini` template too; it stays off, because these colours are canonical
Solarized rather than the 16 ANSI values DMS derives from a palette (`core/internal/dank16`).

## Manual control

```bash
theme-get      # reads ~/.local/state/theme/mode → "dark" | "light"
theme-toggle   # dms ipc call theme toggle
```

Both are installed by the module on Linux. `theme-get` deliberately reads the file rather than
asking the shell, so it also answers in a tty or before DMS is up — `zsh` calls it on every foot
startup to sync a new terminal to the current mode. A manual toggle only holds until the next
scheduled transition.

## Debugging

```bash
# What the shell thinks the mode is, and what the last transition wrote
dms ipc call theme getMode
cat ~/.local/state/theme/mode
journalctl --user -u dms | grep -i matugen

# What the keys actually say
dconf read /org/gnome/desktop/interface/color-scheme
dconf read /org/gnome/desktop/interface/gtk-theme

# What portal-aware apps (Firefox, Slack, …) actually see — 1 = dark, 2 = light, 0 = no preference
busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
  org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance color-scheme
```

If `dconf read` disagrees with `dms ipc call theme getMode`, something re-declared the keys
statically — see the rule at the top. If the portal disagrees with `dconf`, the problem is in
`xdg-desktop-portal-gtk` instead (it is the only registered `org.freedesktop.impl.portal.Settings`
backend; `modules/nixos/core` wires it up via `xdg.portal.extraPortals`).
