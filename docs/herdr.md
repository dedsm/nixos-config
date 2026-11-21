# Herdr

[Herdr](https://herdr.dev) runs terminals and coding agents and shows what every agent is
doing (working, done, idle) across every space. That is why it is here: with several Claude
Code sessions running across `work/<branch>` worktrees, the sidebar answers "which one is
waiting on me" without cycling through windows.

It is two programs: **herdr-core** (`hc`), a headless server that runs terminals and agents
and keeps them running when no window is open, and **herdr-desktop** (`herdr-app`), a GUI
window on top of it that draws its own terminals (Ghostty's VT engine, on Vulkan).

Module: [`modules/home/herdr/default.nix`](../modules/home/herdr/default.nix).
Toggle: `dedsm.herdr.enable`, set in `users/david/shared.nix`: both hosts (see "macOS" below).
It installs `pkgs.unstable.herdr-desktop` and `pkgs.unstable.herdr-core`, sets the theme and
font, and adds Neovim-aware pane navigation. nixpkgs builds both from source and they are
in the binary cache, so nothing compiles locally; the cost is lagging upstream's releases by
a version or two. nixpkgs patches the app to find its own herdr-core; the module also puts
`hc` on `PATH` for shells, agents and the navigation plugin. Layouts, and every setting and
key the module doesn't name, stay the app's own, under `~/.config/herdr-app/`.

Workspaces are called *spaces*, and plugins are JavaScript *mods*. The app's guide to its
own files is `~/.config/herdr-app/AGENTS.md`, rewritten on every start; `herdr-app --skill`
is the short version for agents.

It coexists with tmux (`dedsm.tmux`): separate programs, separate servers.

### The terminal herdr, removed

Until 2026-11 this module was the original terminal herdr (the `herdr` binary, a TUI
multiplexer with a `ctrl+f` prefix, `config.toml` and the `vim-herdr-navigation` plugin),
with herdr-desktop on trial beside it as `dedsm.herdr-desktop`. Upstream's development moved
to herdr-desktop, and the terminal one was dropped; the toggle kept the name. What went with
it: `pkgs/vim-herdr-navigation`, the local appearance-report patch, the `python3` on `PATH`
for herdr's Claude Code integration hook, and the claude-code module's disabled
`Notification` hooks (restored; see "Notifications" below). Its leftovers on disk are not
managed: `~/.config/herdr/` (logs, session state) and, if the integration was never
uninstalled, `~/.claude/hooks/herdr-agent-state.sh` plus its `hooks.SessionStart` entry in
`~/.claude/settings.json`, which does nothing outside a terminal-herdr pane. The git
history before that change has the whole terminal-herdr doc.

## Restarting after an update

A rebuild that bumps either package changes nothing that is already running: the core keeps
its old binary until it is restarted, and the window keeps the app's. To tell, compare what
runs with what is installed:

```bash
hc server status --json | jq -r .version     # the running core
hc --version                                 # the installed core
readlink /proc/$(pgrep -of 'bin/herdr-app( |$)')/exe   # the running app's store path (Linux)
herdr-app --version                          # the installed app
```

If the core differs, `hc server restart`; then quit and reopen the app if it differs too.

Programs keep running through a core restart because the core is two processes:
`herdr-core serve` (the API, the state, the app's connection) and `herdr-core hold`, the
holder, which owns every terminal's pty and is the parent of every program in one. A restart
replaces only `serve`; the new core reattaches to the holder's socket
(`$XDG_RUNTIME_DIR/herdr-core/default.holder.*.sock`). `hc server status --json` lists the
holders and their terminal counts. Terminals kept alive through an update keep their old
holder's behaviour until they are recreated. `hc server stop` is different: it parks kept
terminals and ends the rest, and the next core start gives them fresh shells.

The core hands its own environment to every terminal it starts (see the typing pause
below). Up to 0.1.18 a restart takes the caller's environment; from 0.1.19 it keeps the old
one, and `hc server restart --fresh`, run from a terminal outside Herdr (foot), takes that
shell's environment instead; that is how a changed variable the core reads gets in.

## Notifications

herdr-desktop's toasts are drawn inside its own window, and it sends nothing to the
system's notification service, so it cannot raise one while the window is hidden. Desktop
notifications therefore come from Claude Code's own `Notification`/`UserPromptSubmit` hooks
(`claude-notify.sh` into DMS's notification centre; see [`claude-code.md`](./claude-code.md)).
A layout can name a replacement toast mod that forwards to `notify-send` instead (the
`"toast"` root key, in the app's `AGENTS.md`); none is installed here, since it would only
work while the app runs and would duplicate the hooks.

## What the module writes, and how

Everything goes through the `herdrDesktop` activation step, never a store symlink: the app
watches these files and rewrites some of them.

- **`keys.json` and `settings.json` are merged, the way the Claude Code settings are**
  ([`claude-code.md`](./claude-code.md)): a `jq` deep merge of a base, then the existing
  file, then the managed entries, so whatever the app or you change survives and the
  managed entries are reasserted on every switch. `keys.json` holds every binding, not
  overrides, and the app only writes its defaults when the file is missing, so the base for
  it is the app's shipped `keys.json` (`keys.macos.json` on Darwin, see "macOS"), taken from
  the installed version's source. Putting
  the defaults first also brings new default shortcuts in on an upgrade, which the app
  itself stops doing once the file has been edited; the cost is that a default you delete
  comes back on the next switch, so bind it to `"terminal"` instead to hand the key to the
  program. `settings.json` holds overrides only, so its base is empty. Invalid JSON (a file
  mid-edit) is left alone with a warning.
- **Theme files, the `herdr-nav` layout and the edge-nav mod are copied** into `themes/`,
  `layouts/` and `mods/edge-nav/`, and rewritten only when they change (an identical
  rewrite still makes the app reload them). The mod folder is replaced whole, keyed on its
  store path in `~/.local/state/herdr-desktop/edge-nav.source`; the app does not hot-reload
  a symlinked mod folder.

## Keys

herdr-app's own shortcuts are prefix-free chords. The module adds only what they lack:

- `ctrl+h/j/k/l` → `edge-nav.*`, Neovim-aware pane movement (below), on the chords
  vim-tmux-navigator uses under tmux. The app's own `alt-h/j/k/l` stay bound to plain
  `pane.go`.
- `ctrl+f ctrl+l` → clear screen (`send:` Ctrl+L's byte). `ctrl+l` now moves between
  panes and no default gives a shell its clear screen back, so tmux's `prefix C-l` survives
  as the one key *sequence*: a binding can be several keystrokes, and GPUI holds the first
  as pending input for up to a second (`PENDING_INPUT_TIMEOUT` in the vendored GPUI), so
  the second key must follow within that second.

The defaults worth knowing (Linux; macOS ships cmd-based ones instead):

| Action | herdr-app |
|---|---|
| split right / down | `ctrl-shift-o` / `ctrl-shift-e` |
| zoom, close pane | `ctrl-shift-z`, `ctrl-shift-x` |
| new tab, close tab, rename tab | `ctrl-shift-t`, `ctrl-shift-w`, `f2` |
| next / previous tab, tab N | `ctrl-tab` or `alt-]` / `ctrl-shift-tab` or `alt-[`, `ctrl-1..9` |
| space picker, space N | `ctrl-shift-k`, `alt-1..9` |
| new space, rename space | `ctrl-shift-n`, `shift-f2` |
| sidebar | `ctrl-shift-b` |
| next / previous agent | `alt-down` / `alt-up` |
| settings, help | `ctrl-,`, `ctrl-?` |
| command palette, swap panes | `ctrl-shift-p`, `alt-shift-h/j/k/l` |

No default for: closing a space (space menu, or the palette), detaching (closing the
window does it: herdr-core keeps every terminal), resizing (drag a divider; `layout.resize`
takes a node and a size, not a direction), cycling panes, jumping to agent N, renaming a
pane, copy mode and the scrollback-in-`$EDITOR` dump (`ctrl-shift-f` searches
scrollback), and reloading config (edits apply live). Any of these that has a command can
be bound through `managedKeys` in the module.

## Settings and look

`settings.json` gets Solarized and foot's font: `solarized` and `solarized-light` as a
`{light, dark}` pair, which follows the system appearance (DMS drives it on Linux), and
InconsolataGo Nerd Font Mono at 16px (foot's 12pt; the app sizes in px at zoom 1). The main
layout sets no look of its own, so these decide it. The two theme files are generated from
the shared Solarized terminal palette (`modules/home/theme/solarized.nix`), the one foot's
`colors-dark`/`colors-light` come from too, so a terminal looks the same as in foot and the
module does not depend on foot being configured; their selection colour is base02/base2,
which foot leaves to inversion.

herdr-core gives a lost terminal a fresh shell in its last folder, never its old program;
there is no agent-resume on restore. Sounds are on by default.

## Pane navigation: edge-nav

`ctrl+h/j/k/l` move between panes and are Neovim-aware through
[herdr-app-edge-nav](https://github.com/sebcbi1/herdr-app-edge-nav)
(`pkgs/herdr-app-edge-nav`, MIT): an app mod plus a Neovim plugin in one repo, built as a
Vim plugin. In a pane running nvim the mod sends the chord in with `hc keys`; nvim moves
between its windows and, at its edge, calls `herdr-app do edge-nav.cross-<direction>`.
The other community option, `splits-nav` (TaterDoge/herdr-mods), was passed over: no
licence, a TCP port opened by nvim, and it symlinks itself into `~/.config/nvim/plugin`
and rewrites `keys.json` on its own.

- **Stops at the last pane.** Upstream crosses into the adjacent tab (left/right) or space
  (up/down) at an edge and wraps around; the module turns `TRAVERSE_TABS`,
  `TRAVERSE_SPACES` and `WRAP` off in the copy it installs, to match vim-tmux-navigator.
- **Docking, and the `herdr-nav` layout.** The mod draws nothing, but a key bound to
  `edge-nav.*` reaches it only through a copy docked in the shown layout. The app docks a
  new mod by itself (where its `mod.json` asks: bottom, 0px) **except into a shipped
  layout**: `sync_folders` in its `src/window.rs` skips them, in 0.1.13 and upstream's
  current source alike, so on the shipped `main` every press toasts "unknown command
  edge-nav.down". The module therefore writes `layouts/herdr-nav.json`: the installed
  version's shipped `main.json`, generated on every switch (so it follows upstream changes
  to `main`, unlike a frozen `layout.clone`), with an edge-nav block at 0px at the bottom
  of the `work` column, which has no divider or gap to give it away. Select it once with
  `herdr-app do layout.switch --name herdr-nav` (or `ctrl-shift-l`); the app remembers the
  shown layout in `shared.json`. Another layout of your own needs
  `{ "id": "edge-nav", "type": "block", "size": { "px": 0 }, "content": { "mod": "edge-nav" } }`
  somewhere in its tree.
- **Neovim:** the plugin is added to `programs.neovim.plugins` and maps whatever chords
  `keys.json` binds to `edge-nav.*`, only inside a terminal herdr-desktop shows
  (`$HC_TERMINAL_ID` set); elsewhere it maps nothing and the keys stay vim-tmux-navigator's.
  Inside one both plugins map them from `plugin/`, and vim-tmux-navigator loads later, so
  the module also links `~/.config/nvim/after/plugin/herdr-edge-nav.lua`, which re-runs
  edge-nav's `setup()` after every `plugin/` file has loaded.
- **The core's typing pause is 250 ms, not 3 s.** herdr-core types into a terminal
  (`hc send`, `hc keys`) only once the person typing there has paused for `HC_QUIET_MS`
  (default 3000; `quiet()` in its `src/input.rs`), so an agent's input never lands in the
  middle of yours. edge-nav forwards `ctrl+h/j/k/l` into Neovim with `hc keys`, so at the
  default the first move after typing (leaving insert mode, say) stalled for up to three
  seconds. The module sets `HC_QUIET_MS=250` for the core, which reads it from its own
  environment, i.e. from whatever started it: herdr-app gets it from a wrapper
  (`--set-default`, so it can be overridden), shells from `home.sessionVariables`, and on
  macOS the GUI session from launchd (see "macOS"). A
  running core keeps its environment, so a change takes `hc server restart --fresh` from
  a shell that has it (see "Restarting after an update"). The cost is a smaller guard against an agent typing while you do;
  herdr-core 0.1.20 (in nixpkgs since 2026-11-19) adds a separate draft wait (agent
  messages hold while unsent text sits at a prompt) that covers the worst case of that, a
  half-typed line submitted with the agent's message.
- **Costs:** `ctrl+l`, `ctrl+k` and `ctrl+j` no longer reach a shell. There is no resize:
  edge-nav has none, and the app ships no resize keys (`layout.resize` exists, for a
  binding later).

## macOS

The module is the same on morgoth, with two differences, both because macOS builds of the
app behave differently:

- **The keys base is `keys.macos.json`.** A macOS build compiles in different defaults
  (`DEFAULTS` in `src/keys.rs`): cmd rather than ctrl-shift shortcuts, plus Mac terminal
  editing keys. The managed `ctrl+h/j/k/l` and `ctrl+f ctrl+l` go on top as on Linux; ctrl
  is free there (Aerospace uses alt and the cmd-alt-ctrl hyper chord), and the defaults
  claim neither.
- **`HC_QUIET_MS` reaches the app through launchd.** Herdr.app (copied into
  `~/Applications/Home Manager Apps` with the other home packages, `targets.darwin.copyApps`) runs the bundle's own
  executable when opened from the Dock or Spotlight, not the `bin/herdr-app` wrapper, and
  gets launchd's environment rather than a shell's. A launchd agent, `herdr-env`
  (`org.nix-community.home.herdr-env`), runs `launchctl setenv HC_QUIET_MS 250` at login,
  so the app and every core it starts have it. Shells still get it from
  `home.sessionVariables`.

The theme pair follows macOS's own appearance setting. The running-app check under
"Restarting after an update" reads `/proc`, which macOS lacks; there, quitting and reopening
Herdr after a `darwin-rebuild` that bumps it is the simple answer. Not yet tried on the Mac
itself: the configuration evaluates and both packages are in the binary cache for
`aarch64-darwin`, but nothing here has been run there.

## Open questions

- **Agent status for Claude Code: answered, it works.** herdr-core does not detect agents
  from the screen; an agent has a status only if it reports one through OSC 7501. Claude
  Code 2.1.325 does: its panes show in the agents sidebar as working, done and idle.
- **Light/dark.** The theme pair follows the system appearance; whether a DMS transition
  carries across while the app is open (as it does for Firefox and Slack, through the
  portal) is still to be seen.
- **Telemetry** is on by default in upstream releases; for a source build (which is what
  nixpkgs ships) upstream says it never sends. Settings → Privacy either way.

## Pinning upstream releases instead of nixpkgs

If nixpkgs' lag ever matters, notes for doing it properly:

- Upstream publishes `releases.herdr.dev/{app,core}/latest.json` (URL and sha256 per
  platform), the same shape the Claude Code updater pins from. `hc` is static; `herdr-app`
  needs `autoPatchelfHook` plus RUNPATH entries for the libraries it dlopens (Vulkan,
  Wayland, EGL, `libxkbcommon-x11`) — not a wrapper, whose `LD_LIBRARY_PATH` would leak
  into every terminal.
- A release build self-updates when its binary sits beside `herdr-app.svg`; keep the icon
  under `share/icons` so it never tries to write next to a store path.
- The `keys.json` merge reads the shipped defaults from `pkgs.unstable.herdr-desktop.src`;
  a prebuilt release has no source, so take them from the matching tag of the herdr-app
  repo instead.
