# Agent harness plugins

Module: [`modules/common/users/common/agent-harness/`](../modules/common/users/common/agent-harness/) · flags: `agent-harness.<plugin>.<harness>` (set in `davidShared`).

Some tools plug into every coding agent the same way: rtk rewrites the commands an agent runs, direnv loads the project's environment, and the personal `brain` skill tracks ongoing work. Each agent ("harness") has its own config format for that. This module holds the list of plugins and the per-harness switches in one place, so adding a harness means writing one adapter rather than copying each plugin into its module.

## Flags

```nix
agent-harness = {
  rtk = {
    claude-code = true;
    antigravity = true;
  };
  direnv.antigravity = true;
  rtk-posthook.claude-code = true;
  brain.antigravity = true;
};
```

| Plugin | Supported harnesses | What it installs |
|---|---|---|
| `rtk` | `claude-code`, `antigravity` | the rewrite hook, rtk's awareness text, and `rtk` on `PATH` |
| `direnv` | `antigravity` | a `direnv export` prefix on every command the agent runs |
| `rtk-posthook` | `claude-code` | rtk's `rtk:posthook` pipeline: a PostToolUse hook that compresses tool output after the tool ran — see [below](#rtk-posthook) |
| `brain` | `claude-code`, `antigravity` | the personal `brain` skill and a SessionStart hook with `brain health`'s line, plus (once, whichever harness has it) the `brain` CLI, the `~/brain` bootstrap and commit hooks, and the weekly health notification — see [below](#brain) |

- A harness name is the key of that harness's own module (`claude-code.enable`, `antigravity.enable`). A flag only takes effect where that module is enabled, so the shared `antigravity = true` is inert on morgoth, where Antigravity isn't installed.
- Every flag defaults to `true`. The block in `flake.nix` only spells them out.
- `rtk-posthook` builds on `rtk`, so it is inert in a harness where the `rtk` flag is off.
- Unknown plugins, unsupported pairs (e.g. `direnv.claude-code`) and non-boolean values are evaluation errors, not ignored: a misspelt `false` would otherwise leave a plugin on.
- `davidNixos`/`davidDarwin` extend `davidShared` with `//`, which is shallow. A host override must restate the whole `agent-harness` attrset, not just one flag.

direnv isn't offered for Claude Code because it doesn't need it: its Bash tool inherits the environment of the shell it was started from, which direnv has already loaded for the project.

## rtk's files track the pinned rtk

The awareness text rtk wants agents to read (`~/.claude/RTK.md`, Antigravity's `rules/AGENTS.md`) is **not written in this repo**. `lib.nix` builds `rtk-agent-files-<version>` by running the pinned rtk's own `rtk init -g` (and `--agent antigravity`) against a scratch `HOME` in the build sandbox, and home-manager links the results. The text therefore changes exactly when rtk is bumped. Before this, `RTK.md` was a file `rtk init` had written once by hand, and it still described 0.x commands (`rtk proxy`, renamed `rtk bypass` in 1.0) long after the upgrade. If upstream renames a flag or moves a file, the `install` step fails the build instead of shipping stale text.

Only prose comes from there. The hook entries are written in Nix, because reading rtk's generated JSON back into the evaluation would be import-from-derivation.

rtk is BUSL-1.1 since 1.0 (nixpkgs lists `asl20` + `bsl11`), so it only evaluates because `pkgs.unstable` is imported with `allowUnfree`. Upstream's Apache-only `rtk-oss` edition isn't in nixpkgs. rtk comes from unstable because it moves faster than stable, and nixpkgs carries no updater of our own for it: `nix flake update unstable` bumps it.

## rtk-posthook

rtk 1.0 added a compression engine (the BUSL-1.1 part of the binary; the Apache-only `rtk-oss` edition leaves it out) whose behaviour is described by pipeline files. With none, rtk runs `rtk:default`, which is only the PreToolUse rewrite. This plugin links `~/.config/rtk/pipeline.toml` (`~/Library/Application Support/rtk/` on macOS, which is where rtk looks there) containing just `extends = "rtk:posthook"`, and adds the matching `PostToolUse` hook. The pipeline then compresses output after the tool has run, including output of Claude Code's own tools rather than only rewritten shell commands:

- Bash output rtk had no filter for: ANSI codes and progress bars stripped, repeated lines collapsed (`[x40]`)
- `Read` of `package-lock.json`, `Cargo.lock`, `yarn.lock`, `pnpm-lock.yaml` (not `flake.lock`), replaced by a `name@version` list. The summary only covers what the `Read` returned: a ranged read, or one page of a large lockfile, is summarised on its own. A 40-line read of a pnpm v9 lockfile (whose `packages:` section starts after the importers) came back as `0 packages`, dropping the importer lines that had been asked for, and a full read of a 2,600-line one listed only the first page's 137 packages. To see a lockfile's actual text, use the recovery file or `rtk bypass cat`.
- Grep `content` results, grouped by file; Glob file lists pass untouched
- WebFetch / WebSearch pages

The rules are rtk's, not ours: `rtk pipeline show rtk:posthook` prints them for the pinned version. The two rules that would rewrite every `Read` (`strip-line-numbers`, `json-reads`) ship disabled, which matters because Claude Code's Edit tool needs the exact text it read. Only representation changes, except where the `cap` step fires on long Bash output (over 300 lines: the first 50 and last 200 are kept, the middle becomes `[N lines elided]`) and in the lockfile summaries, and then the hook appends a recovery hint (`[full output: …]`) — a tee file path under the legacy `[tee]` config, or `rtk recall <hash>` after `rtk config recall sqlite`.

It is all local: these rules use built-in transforms only. The pipeline features that call a model (tasks, judges, `rtk:delegate-reads`) need an API key and aren't enabled.

Two build-time guards: the pipeline file is checked with `rtk pipeline validate` while being built, so an rtk bump that drops or renames `rtk:posthook` fails the build instead of rtk silently falling back to its default; and the `PostToolUse` matcher (`Bash|Read|Grep|Glob|WebFetch|WebSearch`) is the tool list `rtk init` registers for this pipeline, so if a later rtk adds rules for another tool, `rtk pipeline validate`/`rtk gain` will report `hook needed: …` until the matcher in `lib.nix` is widened.

The plugin owns `~/.config/rtk/pipeline.toml` outright; a hand-written pipeline belongs in `~/.config/rtk/pipelines/*.toml` or in this module. Upstream applies pipeline hook rules to Claude Code only, hence no Antigravity flag.

## brain

The skill's source sits in the module (`skills/brain/`: `SKILL.md`, `brain.py`, `templates/`) and its build products in `brain.nix`: the CLI, the two `~/brain/.git/hooks` shims, one SessionStart hook per harness, and the weekly notifier. What the skill and store do is in [`brain-skill.md`](./brain-skill.md). This section covers only how the module installs them.

- **One `SKILL.md`, unmodified, in every harness.** Both harnesses read the same skill format (a directory with `SKILL.md` and its `name`/`description` frontmatter), so the file isn't adapted per harness. It refers to its own files relative to itself (`templates/` beside this file), not by a harness's install path, and `templates/` is linked next to it in each harness. Claude Code gets `~/.claude/skills/brain/`. Antigravity gets a plugin at `~/.gemini/config/plugins/brain/` (`plugin.json`, `skills/brain/`, `hooks.json`) rather than a loose `~/.gemini/config/skills/brain/`, so the skill and its hook switch on and off as a unit.
- **The store machinery is per user, not per harness.** The CLI on `PATH`, the bootstrap and hook-refresh activation, and the systemd/launchd timer come in once whenever *any* harness has `brain` active, so Antigravity alone would still get a working store.
- **SessionStart, Claude Code**: `lib.nix` exports `claudeCode.sessionStart`, which the claude-code module puts in `managedSettings.hooks.SessionStart`. That key is shared with herdr's own entry and therefore array-merged (see [`claude-code.md`](./claude-code.md)). The merge drops a stale managed entry by its command path, `~/.local/bin/claude-brain-health.sh`, which is why that path stays stable (this module links the script there) and is exported even when the flag is off.
- **SessionStart, Antigravity**: the plugin's own `hooks.json`. Antigravity's contract is JSON on stdout with the text as an `injectSteps` `systemMessage`, and `{}` when the store is clean.
- **The manual**: `~/brain/AGENTS.md`, which Antigravity loads natively while it works in the store. `~/brain/CLAUDE.md` is only an `@AGENTS.md` import for Claude Code. Both come from `templates/` via `brain sync`.

## Claude Code

- **The hook**: `lib.nix` exports `claudeCode.preToolUse`, which the claude-code module splices into `managedSettings.hooks.PreToolUse`. The harness module does **not** write `~/.claude/settings.json` itself: the claude-code merge replaces arrays (see [`claude-code.md`](./claude-code.md) § Managed settings), so a second writer of `PreToolUse` would delete the other's entries on every switch. With the rtk flag off, the list is `[ ]`, which actively removes a previously merged entry. The command is the bare `rtk hook claude` that `rtk init` writes, so `rtk verify` and `rtk gain` still recognise it as rtk's own hook. That is also why the module puts rtk on `PATH`.
- **`PostToolUse`**: `claudeCode.postToolUse`, from the `rtk-posthook` flag, spliced in the same way and `[ ]` when off. `managedSettings` owns this key outright, so an entry anything else adds to `PostToolUse` is replaced on the next switch (nothing does today); if that changes, it needs the array-merge `SessionStart` already gets.
- **`RTK.md`**: linked from the generated files. Its text is the same with or without the posthook pipeline.
- **`CLAUDE.md`**: `~/.claude/CLAUDE.md` is your own global memory file and stays a regular, editable file. An activation step adds the `@RTK.md` import line when the rtk flag is on and removes exactly that line when it is off. It leaves a symlinked `CLAUDE.md` alone with a warning.

## Antigravity

Antigravity loads every directory under `~/.gemini/config/plugins/`. Apart from the `brain` plugin (above), the module installs one plugin whose `run_command` PreToolUse hook (`antigravity-hook.nix`) runs `rtk hook antigravity` first, then wraps the result in `eval "$(direnv export bash)" && …`. The two must be one hook, since the direnv wrap has to see rtk's rewrite. The plugin is named `rtk` (rtk's own name, as `rtk init --agent antigravity` would install it) whenever rtk is part of it, and `direnv` when only direnv is on. `rules/AGENTS.md` is the generated awareness text.

Antigravity checks permissions after hooks rewrite a command, so a command allowlist has to permit the rewritten form (`command(rtk *)`).

## Adding a harness

Taking Codex as the example (`rtk init -g --codex` writes `~/.codex/{AGENTS.md,RTK.md,hooks.json}`):

1. Add the harness name to the plugin's list in `supported` (`lib.nix`).
2. Generate its files in `rtkAgentFiles`. `--codex` refuses `--auto-patch`, so feed it `</dev/null` instead. Its `AGENTS.md` imports `RTK.md` by absolute path (`@/build/.codex/RTK.md` in the sandbox), so that line has to be rewritten to the installed path.
3. Write the hook, through the harness's own module if it owns the config file (as with Claude Code), or directly from `default.nix` if the plugin directory is entirely ours (as with Antigravity).
4. Add the flag to the block in `flake.nix` and to the table above.
