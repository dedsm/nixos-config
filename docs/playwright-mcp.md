# Playwright MCP

Module: [`modules/common/users/common/playwright/`](../modules/common/users/common/playwright/) · toggle: `playwright.enable` (on by default in `davidShared`).

The Playwright MCP server (used by Claude Code and other MCP clients to drive a real browser) normally downloads and manages its own Chromium build under `~/.cache/ms-playwright`. That duplicates a browser nixpkgs already builds reproducibly, and doesn't play well with a read-only-ish, Nix-managed `$HOME`.

Instead, this module points Playwright at nixpkgs' `playwright-driver.browsers` via environment variables (`home.sessionVariables`):

| Variable | Purpose |
|---|---|
| `PLAYWRIGHT_BROWSERS_PATH` | Points Playwright at the Nix store path containing prefetched browsers instead of `~/.cache/ms-playwright`. |
| `PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS` | Skips a host-dependency check that doesn't understand NixOS. |
| `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` | Never let Playwright fetch its own browser binaries. |
| `PLAYWRIGHT_MCP_EXECUTABLE_PATH` | Resolved at eval time from `playwright-driver.browsersJSON.chromium.revision`, so it always points at the exact Chromium build the pinned `playwright-driver` ships. |
| `PLAYWRIGHT_MCP_USER_DATA_DIR` | `~/.cache/playwright-mcp/profiles` — a stable, persistent browser profile dir for the MCP server (cookies/login state survive across sessions), created by a `home.activation` step. |

Linux-only (`enable && isLinux`): on Darwin, Playwright's own Chromium download works fine natively and nixpkgs' `playwright-driver` browser bundle isn't set up the same way, so the module is a no-op there.

This only configures the *browser*; the actual MCP server registration (which client talks to it, over what transport) lives in each project's `.mcp.json` (gitignored — see [`claude-code.md`](./claude-code.md#mcp-servers)).
