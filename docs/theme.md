# Dark/light theming

The `theme` home-manager module (`modules/common/users/common/theme/default.nix`, opt-in via
`theme.enable` in the composed user config) switches the whole environment between a Solarized
light and dark variant on a schedule — [darkman](https://gitlab.com/WhyNotHugo/darkman) driven by
geoclue on Linux, `dark-notify` driven by `AppleInterfaceStyle` on Darwin.

It owns four things per transition: the GTK/portal color scheme, foot, tmux, and the Hyprland
active-border colour. The Solarized palette itself lives in that module's `colors` attrset and is
also dumped to `~/.colorscheme-palette` as JSON for anything that wants to read it.

## The one rule: darkman owns `color-scheme` and `gtk-theme`

Two dconf keys decide the mode for almost every GUI app on the Linux side:

```
/org/gnome/desktop/interface/color-scheme    prefer-dark | prefer-light
/org/gnome/desktop/interface/gtk-theme       Adwaita-dark | Adwaita
```

`xdg-desktop-portal-gtk` reads them and re-exports them over
`org.freedesktop.portal.Settings` / `org.freedesktop.appearance`; Firefox, Slack and every other
Electron app follow *that*, not the GTK config files. So the chain is:

```
darkman → dconf → xdg-desktop-portal-gtk → org.freedesktop.portal.Settings → Firefox / Slack / …
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

`gtk.theme.package` is gone with `gtk.theme`, so `gnome-themes-extra` is installed via
`home.packages` instead — darkman switches between the `Adwaita` / `Adwaita-dark` pair it ships, so
it still has to be on disk.

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
light mode minutes later on another, hours after darkman correctly switched them to dark. The
usual "fix" is toggling the system to light and back to dark, which re-runs darkman's scripts.

### The activation guard

Removing the static declarations is the actual fix, but `home.activation.reassertColorScheme` in the
`theme` module makes it stick: ordered `after = ["dconfSettings"]`, it re-writes both keys to
whatever mode darkman currently wants, so no activation can leave them stale.

Two details worth knowing:

- It reads `${XDG_CACHE_HOME:-$HOME/.cache}/darkman/mode.txt` rather than calling `darkman get`.
  `darkman get` is a D-Bus call and would fail in the activation service (no session bus), which
  would silently read as "light" — the exact bug it exists to prevent. `home.activation.initTmuxTheme`
  reads the same file, for the same reason.
- It prefers the live user bus (`/run/user/$(id -u)/bus`) when the session is up, so the write emits a
  real `SettingChanged` and apps repaint immediately; it falls back to a throwaway `dbus-run-session`
  at boot, where landing the value in the database is all that matters.

The DAG entry is written out longhand (`{ after; before; data; }`) instead of using
`lib.hm.dag.entryAfter`, because `modules/common/default.nix` `import`s these files with the **NixOS**
`lib` — the home-manager `lib.hm` extensions are not in scope.

## Hyprland border colour

The active-border colour tracks the mode (Solarized blue when dark, red when light). Two things
have to be worked around, both handled in the module's `hyprlandBorder` helper:

- darkman's transition scripts are spawned by the **systemd user manager**, which never inherited
  `HYPRLAND_INSTANCE_SIGNATURE` from the compositor's session. A bare `hyprctl` call just logs
  `HYPRLAND_INSTANCE_SIGNATURE not set! (is hyprland running?)` and does nothing. The signature is
  recovered by iterating `$XDG_RUNTIME_DIR/hypr/*/` and picking the dirs with a live `.socket.sock`.
- Since the Hyprland 0.55 lua-config migration (`configType = "lua"` in
  `modules/common/users/common/hyprland/default.nix`), `hyprctl keyword` is refused outright:
  `keyword can't work with non-legacy parsers. Use eval.` The same option is set through
  `hyprctl eval 'hl.config({ general = { col = { active_border = "rgb(…)" } } })'` instead, which
  applies live — no `hyprctl reload`, and no companion file under `~/.config/hypr`.

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

## Manual control

```bash
theme-get      # darkman get  → "dark" | "light"
theme-toggle   # darkman toggle
```

Both are installed by the module on Linux. Note that a manual toggle only holds until darkman's
next scheduled transition.

## Debugging

```bash
# What darkman thinks the mode is, and its transition history
darkman get
journalctl --user -u darkman | grep "Wanted mode is"

# What the keys actually say
dconf read /org/gnome/desktop/interface/color-scheme
dconf read /org/gnome/desktop/interface/gtk-theme

# What portal-aware apps (Firefox, Slack, …) actually see — 1 = dark, 2 = light, 0 = no preference
busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
  org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance color-scheme
```

If `dconf read` disagrees with `darkman get`, something re-declared the keys statically — see the
rule at the top. If the portal disagrees with `dconf`, the problem is in
`xdg-desktop-portal-gtk` instead (it is the only registered `org.freedesktop.impl.portal.Settings`
backend; `modules/nixos/core` wires it up via `xdg.portal.extraPortals`).
