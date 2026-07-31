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
| Focus left/down/up/right | `ctrl+h` `j` `k` `l` &nbsp;·&nbsp; `prefix+h` `j` `k` `l` |
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

| Agents | |
|---|---|
| Jump to 1–9 | `prefix+ctrl+1` … `prefix+ctrl+9` |
| Next / previous (attention order) | `prefix+a` · `prefix+shift+a` |

| Session | |
|---|---|
| Detach (leaves everything running) | `prefix+q` |
| Reload config · settings · help | `prefix+shift+r` · `prefix+s` · `prefix+?` |

Past nine workspaces the numbered jumps run out, so `prefix+g` is the practical way around a
repo with more worktrees than that. Agents have no such picker — see "Agent navigation".

**Navigate mode** is a separate surface where plain keys work with no prefix: `up`/`down`
move between workspaces, `h`/`j`/`k`/`l` between panes.

### Bindings that ship unset

Upstream leaves these empty, and the herdr docs present some of them as though they were
defaults. This module binds `switch_workspace`, `focus_agent`, `next_agent` and
`previous_agent`; what remains unset is:

`open_worktree` · `remove_worktree` · `previous_workspace` · `next_workspace` · `last_pane`

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

Home Manager 26.05 ships no `programs.herdr` module — the flake pins
`home-manager/release-26.05`, and a grep for "herdr" across its 396 program modules finds
nothing. So the config file is rendered here from a Nix attrset with `pkgs.formats.toml` and
linked with `xdg.configFile`, which keeps the settings readable as Nix — the same shape as
`programs.ghostty.settings` and `programs.starship.settings` — rather than a quoted heredoc.

`modules/programs/herdr.nix` *does* exist on home-manager **master**, and it works exactly
this way: `pkgs.formats.toml` → `xdg.configFile."herdr/config.toml"`, with a free-form
`settings` attrset (its own example sets `onboarding = false`). When it reaches a release the
migration is mechanical — the `settings` binding in this module is already the right shape:

```nix
programs.herdr = {
  enable = true;
  package = pkgs.unstable.herdr;   # the option defaults to pkgs.herdr, i.e. stable
  inherit settings;
};
```

Until then the one thing worth borrowing is its `onChange`, which this module now carries:
`herdr server reload-config || true` after the file changes, so a rebuild applies keybindings
to the running server instead of waiting for the next launch. The `|| true` covers activation
with no server up.

The link is on `herdr/config.toml` specifically, not on the `herdr/` directory. Herdr
writes logs and session state into that directory at runtime, so it has to stay a real
directory rather than a symlink into the store.

## Settings, and why

| Setting | Rationale |
|---|---|
| `onboarding = false` | Skips the first-run notification setup. See "Onboarding and the read-only config" below. |
| `keys.prefix = "ctrl+f"` | Matches the tmux prefix, so muscle memory survives running both. |
| `keys.focus_pane_* = ["prefix+…", "ctrl+…"]` | Prefix-free `ctrl+h/j/k/l` pane movement, the chords `vim-tmux-navigator` owns under tmux. See "Prefix-free pane movement" below for what it costs. |
| `keys.focus_agent` / `next_agent` / `previous_agent` | Reaching an agent directly instead of via its workspace. All three ship unset. See "Agent navigation" below. |
| `ui.agent_panel_sort = "priority"` | Orders the agent panel as an attention queue instead of grouping by workspace, which is what makes `next_agent` mean "next agent waiting on me". See "Agent navigation" below. |
| `ui.mouse_capture = false` | Herdr markets itself mouse-first; this config is keyboard-only, matching `vim.opt.mouse = ""` in the Neovim config. Leaving capture off also passes mouse events through to inner TUIs instead of eating them at the multiplexer. |
| `ui.sidebar.spaces.rows` | Shows `branch` + `git_status` per workspace. With bare repos and many `work/<branch>` checkouts, that is more useful than a pane title. |
| `ui.sidebar.agents.rows_by_agent.claude` | Claude Code writes its current activity to the terminal title, so `terminal_title_stripped` becomes a live "what is this agent doing" column. The override key must be Herdr's canonical agent id. |
| `ui.toast.delivery = "system"` | Herdr owns desktop notifications for every agent; Claude Code's own hooks are disabled to avoid notifying twice. See "Notifications" below. |
| `ui.sound.enabled = true` | Sound on agent state changes in background workspaces. Herdr's default, pinned because the skipped onboarding modal would have asked. |
| `session.resume_agents_on_restore = true` | See "Restart behaviour" below. |
| `theme.*` | Solarized, switching with the host terminal's appearance. See "Theming" below. |

### Onboarding and the read-only config

Herdr shows a first-run notification-setup modal whenever the top-level `onboarding` key is
*missing*, and on dismissal writes `onboarding = false` back into `config.toml`. That write
cannot succeed here — the file is a symlink into the Nix store — so the server logged

```
WARN failed to write config … context="onboarding setting" err="Read-only file system (os error 30)"
```

and the modal returned on every launch. Declaring the post-onboarding value in Nix is the
fix: with `onboarding = false` present, Herdr never opens the modal and never attempts the
write.

The same applies to anything else Herdr persists into `config.toml` at runtime — the
settings overlay (`prefix+s`) can toggle theme, toasts, sound, and a few `ui`/`experimental`
flags, and those toggles will apply for the session but fail to save with the same warning.
Settings changed there have to be moved into the module to survive a restart. Runtime state
that is *not* config (`session.json`, logs, the plugin lock) lives beside it in a real
directory and writes normally.

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
confirms. `herdr config check` only validates that the file parses — it reports `config: ok`
for these bindings — so the only reliable check is `prefix+?`, which lists live bindings. If
either alias is missing there, drop it; the `prefix+v` / `prefix+minus` defaults remain bound either way.

`switch_workspace` ships unset upstream and is bound to `prefix+shift+1..9`. It only reaches
nine, so `goto` (`prefix+g`) remains the way past the ninth worktree.

### Agent navigation

Herdr's agent surface is exactly three actions — an indexed jump plus step forward/back —
and all three ship unset, which left the sidebar read-only: it told you *which* agent was
blocked, and you then reached it by jumping to its workspace. They are bound here:

```toml
focus_agent = "prefix+ctrl+1..9"
next_agent = "prefix+a"
previous_agent = "prefix+shift+a"
```

`ctrl` is the free modifier for the indexed jump: `prefix+1..9` is `switch_tab` and
`prefix+shift+1..9` is `switch_workspace` above.

**`ctrl+digit` is the one uncertain part.** `herdr config check` accepts the binding — and it
genuinely validates rather than rubber-stamping, since `prefix+wibble+1..9` gets
`invalid keybinding … disabling binding` — but that only proves the *config* parses. `ctrl+1`
has no distinct legacy encoding: most terminals send a bare `0x31`, indistinguishable from
plain `1`. Without the kitty keyboard protocol active, `prefix+ctrl+1` would therefore arrive
as `prefix+1` and silently switch *tab* instead, with no error anywhere. Herdr carries the
protocol machinery (`TerminalRuntime::keyboard_protocol`, and the `CSI = …u` / `CSI < u`
push/pop sequences are in the binary) and foot and Ghostty both speak it, so it should
disambiguate — but as with the split aliases above, only pressing it settles this. If it
switches tabs, fall back to upstream's own example of `prefix+alt+1..9`: `alt` survives legacy
encoding as an ESC prefix, at the cost of the macOS Option-key problem on morgoth
(`macos-option-as-alt` is not set in the ghostty module, so Ghostty's default applies).

**Past nine agents there is no picker.** `prefix+w` and `prefix+g` are workspace-only; the
action list in the binary has `WorkspacePicker` and `OpenNavigator` but nothing agent-shaped
that opens one. So the answer past nine is not an indexed key but
`ui.agent_panel_sort = "priority"`, which reorders the agent panel from upstream's
workspace-grouped `"spaces"` default into an attention queue — `next_agent` then walks "next
thing waiting on me" rather than workspace order, which is the useful traversal regardless of
count. The uncapped escape hatch is `herdr agent list` piped into `herdr agent focus <id>`.

### No index column in the sidebar

The workspace numbers `prefix+shift+1..9` refers to are real and exposed by the API —
`herdr workspace list` reports a `number` per workspace — but they cannot be *displayed*. The
space row token table in the binary is exactly `state_icon`, `state_text`, `workspace`,
`branch`, `git_status`, with no index or ordinal token, so `ui.sidebar.spaces.rows` has
nothing to put a number in.

The only lever is the `$name` custom token, fed by `herdr workspace report-metadata
<workspace_id> --source <id> --token num=<n>`. That is a plugin's job rather than a config
setting: herdr's plugin event hooks include `workspace_created`, `workspace_closed` and
`workspace_renamed`, so a plugin could re-push every workspace's number on each of those and
`rows` could then read `$num`. Nothing like that is installed, and it would need re-pushing
for *all* workspaces on every close, since the numbers are positional. Until then `prefix+w`
(picker) and `prefix+g` (fuzzy goto) are the way to pick a workspace by name instead of by
count.

### Prefix-free pane movement

`ctrl+h/j/k/l` move between panes without the prefix — the same chords `vim-tmux-navigator`
owns under tmux — and they are **vim-aware**: inside a Neovim pane they move between Neovim
splits and only cross into the neighbouring Herdr pane at a split edge.

They are not bound to `focus_pane_*` directly. Each is a `[[keys.command]]` entry of
`type = "plugin_action"` pointing at the navigation plugin (see "Plugins" below), which is
what makes the vim-awareness possible; Herdr rejects a key bound twice, so `focus_pane_*`
keeps only its `prefix+h/j/k/l` defaults.

```toml
[[keys.command]]
key = "ctrl+h"
type = "plugin_action"
command = "vim-herdr-navigation.left"
```

`ctrl+alt+h/j/k/l` is Herdr's own suggestion for prefix-free bindings and is deliberately
not used — `CTRL + ALT + L` is bound to `loginctl lock-session` in the Hyprland config on
**manwe**, so "focus pane right" would lock the screen mid-navigation, and diverging per
host is worse than picking a chord that is free on both.

**What this still costs.** Forwarding only happens for Vim/Neovim panes, so in an ordinary
shell pane **`ctrl+l`** (clear screen), **`ctrl+k`** (kill line) and **`ctrl+j`** are
consumed by the navigation. tmux has the same problem and keeps an escape hatch —
`bind C-l send-keys 'C-l'` in `tmux.conf` — which Herdr cannot express: there is no
send-keys *binding* type, only the `herdr pane send-keys` CLI. Use `clear` instead. Other
TUIs that own these chords can be added to the plugin's `HERDR_NAV_PASSTHROUGH_RE`.

`ctrl+h` and Backspace share byte `0x08` unless the kitty keyboard protocol is active. foot
(manwe) and Ghostty (morgoth) both speak it, so Backspace should stay distinct — but that,
like the split aliases above, is only truly settled by trying it.

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

## Notifications

Herdr is the notification system for agents on both hosts. `ui.toast.delivery = "system"`
hands each one to the OS notification service — `notify-send` into swaync on Linux (hence
`libnotify` in the module's `home.packages`; Herdr calls it by name, not by store path),
`osascript`/`display notification` into Notification Center on Darwin. Both paths were
verified in the respective 0.7.5 binaries.

The other deliveries are `herdr` (in-app toasts, useless while detached), `terminal` (OSC
9/777, dependent on the outer terminal), and `off`. `ui.sound.enabled` is independent of
`delivery` and fires on agent state changes in background workspaces;
`[ui.sound.agents] <id> = "off"` mutes one agent if a particular one gets noisy.

### Why not Claude Code's hooks

They are disabled — `Notification = [ ]` and `UserPromptSubmit = [ ]` in the claude-code
module's `managedSettings`. Running both would notify twice for one permission prompt.
Herdr was chosen to own it because:

- it covers **every recognised agent**, not just Claude Code, so a codex or gemini pane
  raises notifications on the same terms;
- `prefix+o` (`open_notification_target`) jumps to the pane that raised the notification,
  which no swaync popup can do;
- the hook path had no Herdr awareness at all — `notify.nix` titles from the **tmux**
  window name and otherwise falls back to the cwd basename, so inside Herdr every
  notification was titled `Claude Code <dirname>`.

What is lost, and worth knowing before deciding it was the right call:

- **Urgency.** The Linux hook raised `permission_prompt`/`idle_prompt` at
  `urgency=critical` and everything else at `normal`. Herdr does not distinguish.
- **Replace-and-dismiss.** The hook tracked a notification id per session in `/tmp` so a
  new notification replaced the previous one, and `UserPromptSubmit` dismissed it once you
  replied. Herdr's notifications stand until the service times them out.
- **Per-type sounds on Darwin.** `cli-notify` played Basso for prompts and Glass for
  completion.

Reverting is a one-line change per hook array; the scripts are still installed. See
[`docs/claude-code.md`](./claude-code.md).

### Two limits of the system delivery

Herdr invokes `notify-send -- <title> <body>` with no flags at all — no `-A/--action`, no
`-u/--urgency`, no `-t/--expire-time` (verified against the string literals adjacent to
`notify-send` in the 0.7.5 binary). Two consequences, both accepted rather than worked
around:

- **Clicking a notification does not jump to the agent.** With no action attached there is
  nothing for swaync to invoke, so a click only dismisses. `prefix+o`
  (`open_notification_target`) is the way to reach the pane that raised one.
- **They expire after 10s.** No `-u` means normal urgency, which lands on swaync's
  `timeout = 10` ([`swaync`](../modules/common/users/common/swaync/default.nix)); only
  `timeout-critical` is `0`/never. Nothing is lost — swaync's control center keeps them,
  and `notification-grouping` is on.

Both are fixable only by the sender. A `notify-send` shim on `PATH` (Herdr calls it by
name, not by store path) could add `-u critical` and an action handler, at the cost of
intercepting every other caller and leaving one blocked process per notification — not
worth it for what it buys.

## Restart behaviour

Detaching (`prefix+q`) leaves the server up and every process running, exactly like tmux.

A reboot stops the server. Herdr restores workspaces, tabs, panes, cwd, layout, and focus
automatically, but the processes themselves are gone and panes return as fresh shells —
the same bargain as tmux-resurrect/continuum.

The difference is `session.resume_agents_on_restore`: supported agents reopen their own
conversation session rather than starting cold. tmux has no equivalent.

That resume is only as good as what the pane recorded, and **it depends on `python3` being
on `PATH`**. Herdr cannot see a Claude session id by itself; the only channel is the
`SessionStart` hook installed by `herdr integration install claude`, which reports
`pane.report_agent_session` (the session UUID plus the transcript path) over `herdr.sock`.
That hook is `sh` for a dozen lines and then a `python3` heredoc — Herdr is Rust, but the
script it writes into the agent's config needs a JSON parser and a unix-socket client in
whatever environment the agent's hooks run in, and it assumes `python3` for the shell-hook
agents the way it assumes node for the `.ts`/`.js` ones. Without it the hook exits **0** at
`command -v python3 >/dev/null 2>&1 || exit 0`, so nothing is reported, no `agent_session`
lands in `session.json`, and there is no id left to build `claude --resume <uuid>` from.

Nothing else here puts a bare `python3` on `PATH` — `brain`, Neovim's `withPython3`, and
`i3xmonadhelper` all resolve an interpreter by store path — so it is listed explicitly in
`davidShared`'s packages in `flake.nix` for this. The failure is silent on both ends (the
hook exits clean, Herdr simply never hears from the pane); `herdr agent list` is what shows
it, as a pane with no `agent_session` field. Pane layout, cwd and focus restore regardless
— that is Herdr's own state and never touches the hook.

Scrollback contents are **not** restored. That needs `[experimental] pane_history`, which
is off by default upstream because terminal history can contain secrets, and is left off
here for the same reason.

## Plugins

One is installed: [`vim-herdr-navigation`](https://github.com/paulbkim-dev/vim-herdr-navigation),
which is what makes `ctrl+h/j/k/l` vim-aware. It is packaged in
[`pkgs/vim-herdr-navigation`](../pkgs/vim-herdr-navigation/default.nix) and registered from
the herdr module — no `herdr plugin install`, no clone-and-build at runtime.

### How registration works

Herdr's plugin registry is `~/.config/herdr/plugins.json`, a plain JSON array. `herdr
plugin link <path>` appends a record to it: the plugin's `herdr-plugin.toml` denormalized
into JSON, plus `plugin_root`, `manifest_path`, `enabled`, and `source.kind = "local"`.
Three properties of that command make it safe from an activation script, all verified
against 0.7.5:

- it does **not** need a running server (it takes `.plugins.lock` and writes the file
  itself; when a server *is* up the CLI routes through the socket and the server persists);
- it is idempotent — linking the same path twice leaves one entry;
- linking a different path for an id already present **replaces** that entry, which is what
  every rebuild does when a plugin's store path changes.

So the module keeps a list of `{ id, root }`, links each at activation, then prunes: any
registry entry whose `plugin_root` is under `/nix/store` but is no longer declared gets
unlinked. Entries linked by hand from outside the store are left alone, so a local
checkout you are hacking on survives a rebuild.

One asymmetry, worth knowing because the error message is misleading: `unlink` *does*
require a running server. `link` and `list` fall back to editing `plugins.json` directly
under `.plugins.lock`; `unlink` has no such fallback — it connects to `herdr.sock`
unconditionally, and with no server the bare `Error: Os { code: 2, kind: NotFound }` it
prints is that missing socket, not a missing plugin (confirmed with `strace`: the failing
call is `connect(AF_UNIX, "…/herdr.sock")`, and nothing under the config dir is ever
opened).

So the prune is best-effort: a plugin dropped from the list lingers in the registry until
the next activation that runs while Herdr is up. In practice rebuilds happen from a
terminal inside Herdr, so that is the common case — verified end to end by linking a
throwaway store-rooted plugin, running the activation script, and watching it disappear
while `vim-herdr-navigation` was re-linked in place.

### Why not a declarative `plugins.json`

Every field of that file is derivable at eval time, so `xdg.configFile` could render it —
but Herdr rewrites it on every link/unlink/enable/disable, and a store symlink is read-only.
That is exactly the failure the `onboarding` setting used to hit, and it would also mean
`herdr plugin enable/disable` silently failing at runtime. Leaving the file mutable and
converging it at activation avoids the whole class.

### Packaging notes

The manifest ships `command = ["bash", "navigate.sh", "<dir>"]`, which assumes a `PATH` and
a working directory. The derivation rewrites those four lines to point at a wrapper that
puts `jq` on `PATH` (without it the plugin degrades to plain focus movement, no Vim
detection) and sets `HERDR_BIN_PATH` to the same `pkgs.unstable.herdr` the user runs.

Upstream tags nothing, so the pin follows the default branch and the version carries the
commit date. Bumping it is `scripts/update-packages.sh vim-herdr-navigation` — the package
carries a `passthru.updateScript` of `nix-update --flake --version=branch`, so there is no
rev or hash to edit by hand. It does *not* move with `nix flake update`.

The editor half is linked to `~/.config/nvim/after/plugin/herdr-nav.lua` by the *herdr*
module, gated on `nvim.enable`. `after/plugin` is what lets it win over the
`vim-tmux-navigator` mappings, and the file itself falls back to `TmuxNavigate*` when
`$HERDR_PANE_ID` is unset — so it is a superset of the tmux setup rather than a conflict,
and needs no `HERDR_ENV` guard. The nvim module links its `config/` recursively and has no
`after/` of its own, so nothing collides.

### The alternatives

All three known ports work the same way as `vim-tmux-navigator`: the Herdr half inspects the
focused pane with `herdr pane process-info` and either forwards the key via `herdr pane
send-keys` or moves focus with `herdr pane focus --direction`, while the editor half falls
out to Herdr when a window is already at the edge.

| Plugin | Shape |
|---|---|
| [`paulbkim-dev/vim-herdr-navigation`](https://github.com/paulbkim-dev/vim-herdr-navigation) | **In use.** The closest 1:1 port of the tmux setup. Herdr plugin plus `editor/nvim.lua`. Has a `HERDR_NAV_PASSTHROUGH_RE` escape hatch for TUIs that never report an edge (lazygit and friends). |
| [`lmilojevicc/herdr-splits.nvim`](https://github.com/lmilojevicc/herdr-splits.nvim) | `smart-splits.nvim` flavour: adds `alt+h/j/k/l` resizing, `at_edge` behaviour, sidebar/float awareness, auto-unzoom. Its `setup()` regenerates `~/.config/herdr/plugins/config/herdr-splits/herdr-splits.conf` — harmless, that is not the store-linked `config.toml` — but its eight keybinds would still have to be declared in this module. |
| [`willfish/herdr-navigator`](https://github.com/willfish/herdr-navigator) | Herdr side only, `alt+h/j/k/l`, pairs with a separate `herdr-navigator.nvim`. |

The plugin-free alternative, if these ever become a maintenance problem, is a small `pkgs/`
script bound with `[[keys.command]] type = "shell"` doing the same `process-info` →
`send-keys`/`focus` dance with no registry involved.

## Deliberately not managed here

**Agent detection.** `herdr integration install claude` writes hooks into the Claude Code
configuration so that Claude reports its own state via `herdr pane report-agent`. It is not
run from this module — the Claude Code setup here already installs hooks of its own (see
[`docs/claude-code.md`](./claude-code.md)), and the two need to be reconciled by hand
before mixing them.

Because state is *pushed* by that integration rather than sniffed from process names, Nix's
`claude` → `.claude-wrapped` wrapper is not an obstacle to detection.

The two do coexist as installed: the merge in the Claude Code module is `jq -s '.[0] * .[1]'`,
which recurses into objects, so its managed `hooks` block leaves the integration's
`SessionStart` entry alone. The one thing provided *for* the integration is the `python3`
its hook needs on `PATH`, in `davidShared`'s packages — see "Restart behaviour" above. The
alternative
considered and rejected was replacing the hook with a Nix-authored one calling
`herdr pane report-agent-session` (the same request, no interpreter needed): it takes
ownership of a file whose own header says reinstalling the integration overwrites it, and
pins Herdr's `v7` field set by hand.

## Verifying

```bash
herdr --version
herdr status                 # server/client health
herdr config check           # parse the rendered config.toml and print diagnostics
herdr agent list             # what it currently recognises as an agent
herdr agent explain <target> --json   # why something was or wasn't detected
herdr server reload-config   # normally automatic via onChange; manual re-apply
herdr plugin list --json     # registered plugins; roots should be store paths
herdr plugin action list     # the actions the keybindings resolve against
herdr plugin log             # what a plugin action actually ran, and its output
```

The rendered config lands at `~/.config/herdr/config.toml` as a symlink into the store;
`herdr --default-config` prints upstream's defaults for comparison.
