# Herdr

[Herdr](https://herdr.dev) is a terminal multiplexer with an agent-awareness layer: a
sidebar shows the lifecycle state (working / blocked / done / idle) of every recognised
agent process across every workspace. That is the reason it is here — with several Claude
Code sessions running across `work/<branch>` worktrees, "which one is waiting on me" is
otherwise answered by cycling through windows.

It is a standalone Rust binary with its own PTY handling and socket API. It does **not**
embed or wrap tmux, so nothing in `programs.tmux` carries over to it.

Module: [`modules/common/users/common/herdr/default.nix`](../modules/common/users/common/herdr/default.nix).
Toggle: `herdr.enable`, set in `davidShared` — both hosts or neither.

## It coexists with tmux

`tmux.enable` and `herdr.enable` are independent and both are on. Separate binaries,
separate servers, separate sockets: a running Herdr server cannot disturb a running tmux
session, and vice versa. Run one in each terminal window and compare them at leisure.

Do not nest them. Two multiplexers stacked in one terminal is a prefix-collision problem
with no upside — launch Herdr from a fresh terminal window, never from inside a tmux pane.
`$HERDR_ENV` is `1` inside a Herdr pane, which is the reliable way to tell.

## Model

Herdr nests one level deeper than tmux, and the extra level maps onto the bare-repo plus
`work/<branch>` layout:

```
Session          one is enough
└─ Workspace     one per worktree
   └─ Tab
      └─ Pane    an ordinary terminal
         └─ Agent   a recognised process, with live state in the sidebar
```

| tmux | Herdr |
|---|---|
| session `carv` | the default session |
| window `carv-os:cos-253-sdk-proposal` | workspace |
| window `carv-os:main 2` | a second *tab* in the `carv-os:main` workspace |
| pane running `.claude-wrapped` | pane, recognised as an agent |
| cycling windows to find the blocked agent | the sidebar |

The `carv-os:main 2` naming exists because tmux windows are a flat namespace. Tabs express
the same thing natively, which is why the herdr renamer needs no dedup pass.

## Getting started

```bash
herdr                        # launch the server and attach
```

Run from any directory and a workspace is created for it. Beyond that, no setup step is
required: `[terminal] new_cwd` defaults to `follow`, so a new workspace, tab, or pane
inherits the source pane's directory, and the zsh hook names the workspace from it. Creating
one needs neither `--cwd` nor `--label`.

Panes are ordinary terminals — run `claude`, an editor, anything. Because panes inherit the
cwd, direnv fires per worktree exactly as it does under tmux.

The CLI equivalents, useful for scripting a layout:

```bash
herdr workspace create --cwd <path> --label <name> --no-focus
herdr workspace list
herdr pane split <pane_id> --direction right|down
```

## Keyboard cheatsheet

The prefix is `ctrl+f`. `prefix+?` lists live bindings and is authoritative over this table.

| Panes | |
|---|---|
| Split right / down | `prefix+v` or `prefix+\|` &nbsp;·&nbsp; `prefix+-` or `prefix+\` |
| Focus left/down/up/right | `prefix+h` `j` `k` `l` |
| Cycle panes forward / back | `prefix+tab` · `prefix+shift+tab` |
| Zoom · close · resize mode | `prefix+z` · `prefix+x` · `prefix+r` |
| Rename pane · scrollback | `prefix+shift+p` · `prefix+e` |

| Tabs | |
|---|---|
| New · rename · close | `prefix+c` · `prefix+shift+t` · `prefix+shift+x` |
| Next / previous | `prefix+n` · `prefix+p` |
| Jump to 1–9 | `prefix+1` … `prefix+9` |

| Workspaces | |
|---|---|
| Picker · fuzzy goto | `prefix+w` · `prefix+g` |
| Jump to 1–9 | `prefix+shift+1` … `prefix+shift+9` |
| New · rename · close | `prefix+shift+n` · `prefix+shift+w` · `prefix+shift+d` |
| New worktree | `prefix+shift+g` |
| Toggle sidebar | `prefix+b` |

| Session | |
|---|---|
| Detach (leaves everything running) | `prefix+q` |
| Reload config · settings · help | `prefix+shift+r` · `prefix+s` · `prefix+?` |

Past nine workspaces the numbered jumps run out, so `prefix+g` is the practical way around a
repo with more worktrees than that.

**Navigate mode** is a separate surface where plain keys work with no prefix: `up`/`down`
move between workspaces, `h`/`j`/`k`/`l` between panes.

### Bindings that ship unset

Upstream leaves these empty, and the herdr docs present some of them as though they were
defaults. Only `switch_workspace` is bound by this module:

`open_worktree` · `remove_worktree` · `previous_workspace` · `next_workspace` ·
`previous_agent` · `next_agent` · `focus_agent` · `last_pane`

`focus_agent`'s documented example uses `prefix+alt+1..9`; upstream's own comment warns that
`alt+…` "may depend on your terminal/tmux setup", which on macOS is the Option-key problem.
Note also that `backslash`, `bracketleft` and `bracketright` are not key names the binary
recognises.

### Creating worktrees

`herdr worktree create` and `prefix+shift+g` default to `[worktrees] directory`, which is
`~/.herdr/worktrees` — a single global path that cannot express the per-repo
`<repo>/work/<branch>` convention used here. Pass the path explicitly:

```bash
herdr worktree create --branch <name> --base main --path <repo>/work/<name>
```

Existing worktrees just need a workspace, via `herdr workspace create --cwd` or
`herdr worktree open --path`.

## Packaging

`pkgs.unstable.herdr` — Herdr is in nixpkgs, and in the unstable revision this flake
already pins, so there is no entry under `pkgs/` and no extra flake input. It builds for
both `aarch64-darwin` and `x86_64-linux`.

Home Manager 26.05 ships no `programs.herdr` module, so the config file is rendered from a
Nix attrset with `pkgs.formats.toml` and linked with `xdg.configFile`. That keeps the
settings readable as Nix — the same shape as `programs.ghostty.settings` and
`programs.starship.settings` — rather than a quoted heredoc.

The link is on `herdr/config.toml` specifically, not on the `herdr/` directory. Herdr
writes logs and session state into that directory at runtime, so it has to stay a real
directory rather than a symlink into the store.

## Settings, and why

| Setting | Rationale |
|---|---|
| `keys.prefix = "ctrl+f"` | Matches the tmux prefix, so muscle memory survives running both. |
| `ui.mouse_capture = false` | Herdr markets itself mouse-first; this config is keyboard-only, matching `vim.opt.mouse = ""` in the Neovim config. Leaving capture off also passes mouse events through to inner TUIs instead of eating them at the multiplexer. |
| `ui.sidebar.spaces.rows` | Shows `branch` + `git_status` per workspace. With bare repos and many `work/<branch>` checkouts, that is more useful than a pane title. |
| `ui.sidebar.agents.rows_by_agent.claude` | Claude Code writes its current activity to the terminal title, so `terminal_title_stripped` becomes a live "what is this agent doing" column. The override key must be Herdr's canonical agent id. |
| `session.resume_agents_on_restore = true` | See "Restart behaviour" below. |
| `theme.*` | Solarized, switching with the host terminal's appearance. See "Theming" below. |

### Theming

```toml
[theme]
auto_switch = true
dark_name = "solarized"
light_name = "solarized-light"
name = "solarized"
```

`auto_switch` follows the **host terminal's** light/dark appearance, not the OS and not a
notification daemon. That is why Herdr needs none of the bridge that
[`theme/default.nix`](../modules/common/users/common/theme/default.nix) builds for tmux —
no darkman scripts on manwe, no `dark-notify` agent or `theme-apply` symlink dance on
morgoth. It detects the transition itself, identically on both hosts.

`solarized` / `solarized-light` are exact built-in identifiers (verified against the
binary's theme table, alongside `catppuccin-latte`, `gruvbox-light`, `one-light`,
`tokyo-night-day`, `kanagawa-lotus`, `rose-pine-dawn`, `nord`, `dracula`, `vesper`). They
match the Solarized palette the `theme` module already applies to tmux and the Hyprland
borders.

`name` is set as well because `auto_switch` only chooses between `dark_name` and
`light_name` when detection succeeds; without a base name, a failed detection falls back to
Herdr's catppuccin default.

There is also a `name = "terminal"` theme that adopts the host terminal's ANSI palette
directly. That would track Ghostty's `Selenized` exactly rather than approximating it with
Solarized, but whether it re-reads the palette when the terminal switches modes is not
documented, so the explicit pair is used instead.

### Splits and workspace jumps

`split_vertical` and `split_horizontal` carry the herdr defaults plus tmux-style aliases —
`|` splits right, `\` splits down, matching `bind |` / `bind \\` in `tmux.conf`. herdr names
a split after the divider it draws, so its "vertical" is tmux's `split-window -h`.

**These two aliases are unverified.** `backslash`, `bracketleft` and `bracketright` appear
nowhere in the binary, so `\` has no *named* form — it is bound here as a literal printable
key, which the documented syntax ("plain keys") should accept but which nothing offline
confirms. There is no config validator: `herdr status` parses the file without checking key
names, and the only reliable check is `prefix+?`, which lists live bindings. If either alias
is missing there, drop it; the `prefix+v` / `prefix+minus` defaults remain bound either way.

`switch_workspace` ships unset upstream and is bound to `prefix+shift+1..9`. It only reaches
nine, so `goto` (`prefix+g`) remains the way past the ninth worktree.

### No prefix-free chords

Herdr's docs recommend `ctrl+alt+…` for prefix-free bindings, but `CTRL + ALT + L` is
already bound to `loginctl lock-session` in the Hyprland config on **manwe**. Binding it to
"focus pane right" would lock the screen mid-navigation.

Rather than diverge per host, no bare chords are bound on either. Pane movement is
`prefix+h/j/k/l` everywhere. If a seamless-navigation plugin is added later it will own
`ctrl+h/j/k/l` directly and the question goes away.

## Automatic workspace naming

Workspaces are renamed on `chpwd` by `_herdr_rename_workspace` in the
[`zsh`](../modules/common/users/common/zsh/default.nix) module — the herdr counterpart to the
existing `_tmux_rename_window`. Both now share `_workspace_display_name`, which produces
`repo:dir` for a checkout whose directory differs from its repository name and the bare
basename otherwise:

```
~/Develop/Carv/carv-os/work/main                 -> carv-os:main
~/Develop/Carv/carv-os/work/cos-253-sdk-proposal -> carv-os:cos-253-sdk-proposal
~/Develop/Carv/carv-sdk/work/main                -> carv-sdk:main
~/Develop/Carv/carv-ats                          -> carv-ats
```

It reads `$HERDR_WORKSPACE_ID` from the pane environment and no-ops when `$HERDR_ENV` is
unset, so it costs nothing outside herdr. Because `[terminal] new_cwd` defaults to `follow`,
a new workspace inherits the source pane's directory and then names itself — creating one
needs no `--cwd` and no `--label`.

Unlike the tmux renamer this does **no** dedup pass. tmux's ` 2` suffix exists because
windows are a flat namespace; in herdr a second view of one worktree is a tab inside the
workspace, so the labels don't collide. `herdr workspace list` also has no `--json` mode,
which would make a dedup pass depend on parsing human-readable output.

Renaming is per *workspace*, so in a workspace holding panes in different directories the
last `cd` wins — the same behaviour the tmux hook already has for a window holding several
panes.

## Restart behaviour

Detaching (`prefix+q`) leaves the server up and every process running, exactly like tmux.

A reboot stops the server. Herdr restores workspaces, tabs, panes, cwd, layout, and focus
automatically, but the processes themselves are gone and panes return as fresh shells —
the same bargain as tmux-resurrect/continuum.

The difference is `session.resume_agents_on_restore`: supported agents reopen their own
conversation session rather than starting cold. tmux has no equivalent.

Scrollback contents are **not** restored. That needs `[experimental] pane_history`, which
is off by default upstream because terminal history can contain secrets, and is left off
here for the same reason.

## Deliberately not managed here

**Plugins.** `herdr plugin install <owner>/<repo>` clones from GitHub and runs build
commands as a runtime side effect, which does not belong in a Nix closure. `herdr plugin
link <path>` skips the build step and can point at a store path, but registration is still
a call against a running server. Nothing is wired up for this yet; add plugins by hand and
they persist in Herdr's own state.

**Agent detection.** `herdr integration install claude` writes hooks into the Claude Code
configuration so that Claude reports its own state via `herdr pane report-agent`. It is not
run from this module — the Claude Code setup here already installs hooks of its own (see
[`docs/claude-code.md`](./claude-code.md)), and the two need to be reconciled by hand
before mixing them.

Because state is *pushed* by that integration rather than sniffed from process names, Nix's
`claude` → `.claude-wrapped` wrapper is not an obstacle to detection.

## Verifying

```bash
herdr --version
herdr status                 # server/client health
herdr agent list             # what it currently recognises as an agent
herdr agent explain <target> --json   # why something was or wasn't detected
herdr server reload-config   # after a rebuild, without restarting the server
```

The rendered config lands at `~/.config/herdr/config.toml` as a symlink into the store;
`herdr --default-config` prints upstream's defaults for comparison.
