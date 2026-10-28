# Google Antigravity

Module: [`modules/home/antigravity/`](../modules/home/antigravity/) · toggle: `dedsm.antigravity.enable` (on in `users/david/nixos.nix`, not in `shared.nix` — this is Linux-only, see [Darwin](#darwin)), with per-component sub-toggles `dedsm.antigravity.hub.enable`, `.ide.enable`, `.cli.enable`, all on by default.

Antigravity 2.0 split the product into three separately-shipped artifacts, and this config installs all three:

| Component | Binary | Package |
|---|---|---|
| Hub — the 2.0 agent-orchestration app | `antigravity` | `pkgs.unstable.antigravity-hub` |
| IDE — the legacy 1.x editor, still maintained | `antigravity-ide` | `pkgs.unstable.antigravity-ide` |
| CLI | `agy` | `pkgs.unstable.antigravity-cli` |

The three binaries don't collide, so all of them can be on `PATH` at once. All three are unfree binaries, named on `pkgs.unstable`'s allowlist in [`lib/pkgs.nix`](../lib/pkgs.nix).

The rtk + direnv `run_command` hook plugin under `~/.gemini/config/plugins/` isn't installed by this module but by the agent-harness one, switchable via `agent-harness.rtk.antigravity` and `agent-harness.direnv.antigravity` — see [`agent-harness.md`](./agent-harness.md).

## Why unstable, and the input it replaced

Until 2026-10-29 all three came from the [`jacopone/antigravity-nix`](https://github.com/jacopone/antigravity-nix) flake input, because nixpkgs trailed Google's releases badly: on 2026-10-15 `unstable` had hub 2.12.2 against upstream's 2.21.0. By 2026-10-29 the gap was down to a few point releases (hub 2.25.0 vs 2.28.0, IDE 2.5.5 vs 2.6.0, CLI 1.4.8 vs 1.4.9), so the input was dropped. **Updating is `nix flake update unstable`**, like every other `pkgs.unstable` package.

The nixpkgs packages are built differently from the input's, and the differences are why switching cost nothing:

- **No FHS sandbox.** The input's GUI packages defaulted to a `buildFHSEnv` bubblewrap sandbox, whose *no new privileges* flag breaks `sudo` in the integrated terminal, so this config had to pass `useFHS = false`. nixpkgs' hub is a plain `autoPatchelfHook` build and its IDE goes through `buildVscode`, the same builder as VS Code; neither runs in bubblewrap.
- **No `google-chrome`.** The input's wrappers pointed the browser agent at a Chrome shim (`CHROME_BIN`/`CHROME_PATH`), which put `google-chrome` (~435 MiB, unfree) in the closure even with the shared Chrome profile turned off. nixpkgs' packages don't reference a browser at all. Whether the hub's browser agent finds one on its own without that wiring hasn't been checked here.
- **Wayland** comes from nixpkgs' usual `NIXOS_OZONE_WL`-gated flags (the hyprland module sets it).

If nixpkgs falls badly behind again, the input's package files can be `callPackage`d from `pkgs/default.nix` against `unstablePkgs` once more (see the history of this file for the `useFHS = false` / `useUserProfile = false` arguments that needed).

## The IDE keyring flag

On Linux the IDE stores credentials in the desktop keyring, and Electron's autodetection doesn't reliably find it outside a GNOME session, so it needs `--password-store=gnome-libsecret` (the same flag this config passes to VS Code). nixpkgs' IDE takes a `commandLineArgs` argument like every `buildVscode` package, so the module passes it through `.override`.

## Darwin

**Antigravity is not installed on macOS at all** — it isn't used there, so `dedsm.antigravity.enable` is set in `users/david/nixos.nix` rather than `shared.nix`. nixpkgs' three packages do support `aarch64-darwin` (the hub installs `Applications/Antigravity.app` plus a `bin/antigravity` wrapper), so moving the toggle into `shared.nix` should be enough if that ever changes, but it hasn't been tried.
