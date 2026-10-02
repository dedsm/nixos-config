# caveman

Package: [`pkgs/caveman/`](../pkgs/caveman/) · installed via `davidShared`'s package list (`pkgs.local.caveman`), so both hosts get it.

[caveman](https://github.com/JuliusBrussee/caveman) compresses what a coding agent *reads*. `caveman claude` starts Claude Code with `ANTHROPIC_BASE_URL` pointed at a local proxy (`127.0.0.1:8787`). The proxy rewrites large tool results (JSON, logs, diffs, code) into shorter forms using fixed rules, and stores the exact originals in `~/.caveman/ccr.db` so the model can fetch them back over MCP. It complements rtk rather than replacing it. rtk filters Bash output when a command runs; the proxy sees every tool result, including Read, MCP and WebFetch output.

This is the proxy/CLI side only. The caveman *skill* (terse output) is a Claude Code plugin and is not managed here.

## Two derivations

| Attr | Source | What it is |
|---|---|---|
| `caveman-bin` | `fetchFromGitHub`, tag `bin-v<version>`, built with `buildGoModule` | `caveman-proxy`, `-engine`, `-mcp`, `-shrink`, `-browse` and `cavemem` |
| `caveman` | the npm tarball `@caveman-ai/cli` | the `caveman` / `cave` CLI, a self-contained JS bundle with no runtime deps, run with `nodejs_22` |

Upstream's install path is `npm i -g @caveman-ai/cli && caveman setup --install`. The second step downloads signed Go binaries into `~/.caveman/bin` at runtime. Here they are built from source instead, the same way upstream's `scripts/build-release-binaries.mjs` builds them: `go build -trimpath` with `CGO_ENABLED=0`, and SQLite comes from pure-Go `modernc.org/sqlite`. The results are static, so nothing needs patching on NixOS.

The CLI's wrapper pins each binary with `--set-default CAVEMAN_*_BIN` (plus `CAVEMEM_BIN`). Those env vars take priority over `PATH` and `~/.caveman/bin`, so the CLI always uses the store build. `caveman setup` should report every binary under `/nix/store`.

`caveman-bin` uses `pkgs.unstable`'s `buildGoModule`, because upstream's `go.mod` asks for a newer Go than stable carries.

One upstream test is skipped (`checkFlags`): `TestRunStatusRequiresThisListenerGeneration` inspects the test process's own name and liveness, which the build sandbox hides.

## Telemetry

Upstream's CLI sends usage telemetry by default in interactive shells. The wrapper sets `CAVEMAN_TELEMETRY=0` with `--set-default`, so it is off unless you export `CAVEMAN_TELEMETRY=1` yourself.

## Updating

Both attrs carry a `passthru.updateScript`, so `scripts/update-packages.sh caveman-bin caveman` bumps them:

- `caveman-bin` runs `nix-update --version-regex 'bin-v(.*)'`, because upstream tags each component separately (`bin-v*`, `cli-v*`, `sdk-*`, …).
- `caveman` runs plain `nix-update`, which reads the npm registry's `latest`.

The two must move together. The CLI probes its binaries for the capabilities of the binary release it was cut against (`BINARY_RELEASE` in `dist/binaries.generated.js`). The `caveman` install phase checks that value against `caveman-bin.version` and fails the build on a mismatch, so a half-done bump breaks `nix build` instead of quietly turning off compression at runtime.

## Interaction with the Claude Code module

`caveman claude` itself only sets env vars for the Claude Code process. Some other caveman commands write hooks into `~/.claude/settings.json`:

- **Shrink hook** (`PreToolUse` on `Bash`): rewrites noisy commands through `caveman shrink`. It overlaps with rtk's hook, so leave it off unless you mean to replace rtk.
- **Auto-recall hook** (`UserPromptSubmit`, opt-in): the [Claude Code module](./claude-code.md) sets `hooks.UserPromptSubmit = [ ]` in its managed settings, so every switch would delete this hook. If you want it, it has to move into `managedSettings`.
