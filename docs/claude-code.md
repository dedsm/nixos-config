# Claude Code setup

Module: [`modules/home/claude-code/`](../modules/home/claude-code/) · toggle: `dedsm.claude-code.enable` (on in `users/david/shared.nix`).

## Package pinning

`claude-code` moves fast enough that `pkgs.unstable.claude-code` alone isn't reliable, so the
module pins an exact release. The pin is upstream's *own* release manifest — `manifest.zst.json`
in the module directory, stored byte-for-byte as published — handed back to nixpkgs' package
through its `manifest` argument:

```nix
claudeCodePkg = pkgs.unstable.claude-code.override {
  manifest = lib.importJSON ./manifest.zst.json;
};
```

nixpkgs then derives the version, download URL, artifact name and per-platform checksum from
it, exactly as it does for its own vendored manifest. Bump the pin with:

```bash
scripts/update-packages.sh claude-code              # defaults to latest
scripts/updaters/update-claude-code.sh [version]   # or call it directly, e.g. to pin an older release
```

The updater is a single `curl` of that manifest — no transformation, nothing local to fall
out of date. Commit the result.

**Why not `overrideAttrs` on `src`/`version`?** That's what this module did until
`manifest.zst.json` replaced `version.json`, and it broke: re-stating upstream's URL scheme
and artifact layout locally meant that when Anthropic moved releases to
`downloads.claude.ai` and started shipping zstd-compressed `claude.zst` artifacts, nixpkgs'
`installPhase` switched to `unzstd` while our hand-rolled `src` kept fetching a raw binary —
`zstd: unsupported format`, on a pin that still *evaluated* cleanly. Overriding the `manifest`
argument keeps the fetching contract entirely upstream's, so a change of that shape lands as
a plain nixpkgs bump instead of a build failure here.

The updater is a script rather than a `passthru.updateScript` because the pin is a whole JSON
file rather than a hash in a `.nix` file — `nix-update` can rewrite one hash and nothing else.
nixpkgs' own `claude-code` uses a bespoke `update.sh` for the same reason. Any executable
`scripts/updaters/update-<name>.sh` is picked up by `scripts/update-packages.sh`
automatically; see "Updating pinned packages" in [`CLAUDE.md`](../CLAUDE.md).

Note that `nix flake update` does **not** move Claude Code: `manifest.zst.json` overrides
whatever `pkgs.unstable.claude-code` carries, so the version only changes when this updater
runs.

## Managed settings, not owned settings

`~/.claude/settings.json` is user-editable (slash commands, project state, etc.), so this module never overwrites it wholesale. Instead `default.nix` defines a `managedSettings` attrset (hooks, status line, file-suggestion command, `alwaysThinkingEnabled`, attribution, and an `env` block — see [Task tools](#task-tools), [Web search cap](#web-search-cap) and [Telemetry](#telemetry)) and a `home.activation.mergeClaudeSettings` step that JSON-merges it into the existing file (`jq -s '.[0] * .[1]'`) on every `home-manager switch`. Anything Claude Code itself writes into `settings.json` survives; anything under `managedSettings` gets reasserted every rebuild. Extend it via the `dedsm.claude-code.extraSettings` option instead of editing the merge logic. One key is special-cased: `hooks.SessionStart` is **array-merged** rather than replaced, because herdr's integration installs its own entry there (see [`herdr.md`](./herdr.md)) — user entries survive every switch, and the managed brain-health entry is appended (deduped by command path).

## Task tools

`managedSettings.env` sets `CLAUDE_CODE_ENABLE_TODO_TOOLS = "1"`, which exposes the
`TaskCreate`/`TaskGet`/`TaskList`/`TaskUpdate` tools to the model. Without it those tools are
withheld for the models on Claude Code's internal gate list, and `TodoWrite` is gated off by
the same switch — so a session gets *no* task tracking at all, with nothing in `/doctor` or
`/config` to say why. The gate: model not on the list → tools on; else this env var → tools
on; else a server-side feature flag decides (off unless the account is in the rollout).

Verify on any host with:

```bash
claude -p ok --output-format=stream-json --verbose --max-turns 1 \
  | jq -c 'select(.subtype=="init") | {model, task: [.tools[] | select(startswith("Task"))]}'
```

`Task`, `TaskOutput` and `TaskStop` are unrelated (subagents and background processes) and are
present either way; the four above are the ones that come and go.

## Web search cap

`managedSettings.env` also sets `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION = "10000"`, which
raises the number of `WebSearch` calls allowed in a single session to effectively unlimited,
so long research sessions aren't cut off partway through.

## Telemetry

`managedSettings.env` sets `DISABLE_TELEMETRY = "1"` and `DISABLE_ERROR_REPORTING = "1"`, which
stop Claude Code sending usage metrics and error reports to Anthropic
([data usage](https://code.claude.com/docs/en/data-usage)). `DISABLE_TELEMETRY` also disables the
session-quality survey and feature-flag evaluation, so Remote Control (and anything that relies on
it, such as mobile push) may be unavailable. Prompts and code still go to the model;
whether Anthropic trains on them is the account toggle at
<https://claude.ai/settings/data-privacy-controls>, not something this module controls.

## Hooks

All hook scripts are generated Nix strings (`home.file.".local/bin/claude-*.sh"`), so they're reproducible and platform-aware (`isDarwin` branches inside `notify.nix`/`dismiss.nix`):

- **`PreToolUse` / `PostToolUse` → `rtk hook claude`**: owned by the agent-harness module (`dedsm.agent-harness.rtk.claude-code` for the command rewrite, `dedsm.agent-harness.rtk-posthook.claude-code` for compressing tool output after it ran), which this module splices in from `agent-harness/lib.nix` so that it stays the only writer of `settings.json`. Each is `[ ]` when its flag is off. See [`agent-harness.md`](./agent-harness.md), which also covers `~/.claude/RTK.md` and the `@RTK.md` line in `~/.claude/CLAUDE.md`.
- **`Notification` and `UserPromptSubmit`**: **disabled** — `[ ]` in `managedSettings`. Desktop notifications are delivered by herdr instead (`ui.toast.delivery = "system"`), which covers every recognised agent rather than only Claude Code and can jump to the pane that raised one. See "Notifications" in [`herdr.md`](./herdr.md) for the trade-off, including what the hooks did better.

  They are empty *lists* rather than deleted keys on purpose: the merge is `jq -s '.[0] * .[1]'`, so a key dropped from `managedSettings` leaves whatever is already in `~/.claude/settings.json` untouched — the hooks would keep firing. Assigning `[ ]` actively overwrites them.

  `claude-notify.sh` and `claude-dismiss-notification.sh` are still generated and installed, and the `dedsm.claude-code.notifyScript`/`dismissScript` options still work, so restoring the old behaviour is a one-line revert of each hook array. `notify.nix` titles its notification from the **tmux** window name (`$TMUX`/`$TMUX_PANE`) and falls back to the cwd basename, so it never had herdr-aware titles; that gap is why the split was worth resolving one way or the other.
- **`SessionStart` → `claude-brain-health.sh`** (from the agent-harness module's `brain` plugin, via `agentHarness.claudeCode.sessionStart`; `[ ]` when `dedsm.agent-harness.brain.claude-code` is off, and the merge still drops a stale copy by its command path): surfaces `brain health`'s one-line store vitals when a session starts (matcher `startup|resume|clear` — deliberately not `compact`, which would repeat the line mid-task). It emits **JSON**, not plain text, because the flag has two audiences and a hook's plain stdout only reaches one of them: stdout becomes Claude's context, so the user wouldn't see the flag until Claude's first reply. The object carries `systemMessage` (rendered to the user directly, at session start) *and* `hookSpecificOutput.additionalContext` (the context injection), so one run reaches both. `brain health`'s line is arbitrary text, so `jq -n --arg` builds the object rather than string interpolation. Fail-open (always exits 0) and silent — no output at all — when the store is clean or absent. The same check also runs on a weekly timer (systemd user timer / launchd agent) that raises a desktop notification — see [`brain-skill.md`](./brain-skill.md) § Ambient surfacing.
- **`fileSuggestion` → `claude-file-suggestion.sh`**: `@`-mention file completion backed by `fd` + `fzf` instead of Claude Code's default walk, so it respects `.gitignore`-style excludes and is fast in large repos.
- **`statusLine` → `claude-statusline.sh`**: two-line status line — model, context window usage (colored by % used), input/output/cache token counts, 5h/7d rate-limit usage with reset countdowns (`↻ 8h05m`, whole days such as `↻ 2d` once 24h or more away), and git branch/worktree/dirty state for the current directory.

## Editor integration

The `nvim` module (see [`nvim.md`](./nvim.md)) pulls in `claude-code-nvim` and binds `<leader>cc` / `<leader>cR` to toggle an in-editor Claude Code terminal — see `modules/home/nvim/config/lua/config/claude-code.lua`.

## MCP servers

Project-level MCP server config lives in `.mcp.json` at the repo root — **gitignored on purpose** (`.gitignore`), since it's machine-local and can carry connection secrets. The Playwright MCP server itself is documented separately: see [`playwright-mcp.md`](./playwright-mcp.md).

## The `brain` skill

The personal `brain` tracking skill used to ship from this module. It is now the agent-harness module's `brain` plugin, so Antigravity gets it too. This module only splices in its SessionStart hook. See [`brain-skill.md`](./brain-skill.md) and [`agent-harness.md`](./agent-harness.md).
