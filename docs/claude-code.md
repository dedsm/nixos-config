# Claude Code setup

Module: [`modules/common/users/common/claude-code/`](../modules/common/users/common/claude-code/) · toggle: `claude-code.enable` (on by default in `davidShared`, see `flake.nix`).

## Package pinning

`claude-code` moves fast enough that `pkgs.unstable.claude-code` alone isn't reliable. `version.json` in the module directory pins an exact version + per-platform sha256, and `default.nix` overrides `pkgs.unstable.claude-code`'s `src`/`version` with it when present. Bump the pin with:

```bash
scripts/update-packages.sh claude-code              # defaults to latest
scripts/updaters/update-claude-code.sh [version]   # or call it directly, e.g. to pin an older release
```

This fetches the release manifest and rewrites `version.json`. Commit the result.

The updater is a script rather than a `passthru.updateScript` because the pin is a JSON file
holding *two* platform hashes, with the version coming from a release manifest rather than a
Git tag — `nix-update` can rewrite one hash in a `.nix` file and nothing else. nixpkgs' own
`claude-code` uses a bespoke `update.sh` for the same reason. Any executable
`scripts/updaters/update-<name>.sh` is picked up by `scripts/update-packages.sh`
automatically; see "Updating pinned packages" in [`CLAUDE.md`](../CLAUDE.md).

Note that `nix flake update` does **not** move Claude Code: `version.json` overrides whatever
`pkgs.unstable.claude-code` carries, so the version only changes when this updater runs.

## Managed settings, not owned settings

`~/.claude/settings.json` is user-editable (slash commands, project state, etc.), so this module never overwrites it wholesale. Instead `default.nix` defines a `managedSettings` attrset (hooks, status line, file-suggestion command, `alwaysThinkingEnabled`, attribution, and an `env` block that sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`) and a `home.activation.mergeClaudeSettings` step that JSON-merges it into the existing file (`jq -s '.[0] * .[1]'`) on every `home-manager switch`. Anything Claude Code itself writes into `settings.json` survives; anything under `managedSettings` gets reasserted every rebuild. Extend it via the `extraSettings` option instead of editing the merge logic.

## Hooks

All hook scripts are generated Nix strings (`home.file.".local/bin/claude-*.sh"`), so they're reproducible and platform-aware (`isDarwin` branches inside `notify.nix`/`dismiss.nix`):

- **`Notification` and `UserPromptSubmit`**: **disabled** — `[ ]` in `managedSettings`. Desktop notifications are delivered by herdr instead (`ui.toast.delivery = "system"`), which covers every recognised agent rather than only Claude Code and can jump to the pane that raised one. See "Notifications" in [`herdr.md`](./herdr.md) for the trade-off, including what the hooks did better.

  They are empty *lists* rather than deleted keys on purpose: the merge is `jq -s '.[0] * .[1]'`, so a key dropped from `managedSettings` leaves whatever is already in `~/.claude/settings.json` untouched — the hooks would keep firing. Assigning `[ ]` actively overwrites them.

  `claude-notify.sh` and `claude-dismiss-notification.sh` are still generated and installed, and the `notifyScript`/`dismissScript` options still work, so restoring the old behaviour is a one-line revert of each hook array. `notify.nix` titles its notification from the **tmux** window name (`$TMUX`/`$TMUX_PANE`) and falls back to the cwd basename, so it never had herdr-aware titles; that gap is why the split was worth resolving one way or the other.
- **`fileSuggestion` → `claude-file-suggestion.sh`**: `@`-mention file completion backed by `fd` + `fzf` instead of Claude Code's default walk, so it respects `.gitignore`-style excludes and is fast in large repos.
- **`statusLine` → `claude-statusline.sh`**: two-line status line — model, context window usage (colored by % used), input/output/cache token counts, 5h/7d rate-limit usage with reset countdowns, and git branch/worktree/dirty state for the current directory.

## Editor integration

The `nvim` module (see [`nvim.md`](./nvim.md)) pulls in `claude-code-nvim` and binds `<leader>cc` / `<leader>cR` to toggle an in-editor Claude Code terminal — see `modules/common/users/common/nvim/config/lua/config/claude-code.lua`.

## MCP servers

Project-level MCP server config lives in `.mcp.json` at the repo root — **gitignored on purpose** (`.gitignore`), since it's machine-local and can carry connection secrets. The Playwright MCP server itself is documented separately: see [`playwright-mcp.md`](./playwright-mcp.md).

## The `brain` skill

This module also ships and bootstraps the personal `brain` tracking skill. See [`brain-skill.md`](./brain-skill.md).
