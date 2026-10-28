# Google Antigravity

Module: [`modules/home/antigravity/`](../modules/home/antigravity/) · toggle: `dedsm.antigravity.enable` (on in `users/david/nixos.nix`, not in `shared.nix` — this is Linux-only, see [Darwin](#darwin)), with per-component sub-toggles `dedsm.antigravity.hub.enable`, `.ide.enable`, `.cli.enable`, all on by default.

Antigravity 2.0 split the product into three separately-shipped artifacts, and this config installs all three:

| Component | Binary | Package |
|---|---|---|
| Hub — the 2.0 agent-orchestration app | `antigravity` | `pkgs.local.antigravity-hub` |
| IDE — the legacy 1.x editor, still maintained | `antigravity-ide` | `pkgs.local.antigravity-ide` |
| CLI | `agy` | `pkgs.local.antigravity-cli` |

The three binaries don't collide, so all of them can be on `PATH` at once.

The rtk + direnv `run_command` hook plugin under `~/.gemini/config/plugins/` isn't installed by this module but by the agent-harness one, switchable via `agent-harness.rtk.antigravity` and `agent-harness.direnv.antigravity` — see [`agent-harness.md`](./agent-harness.md).

## Why not nixpkgs

nixpkgs has all three now — `antigravity-hub` landed in [NixOS/nixpkgs#524225](https://github.com/NixOS/nixpkgs/pull/524225) (merged 2026-09-20, at 2.12.2) — but they **trail upstream**, because Google ships new tarballs faster than the nixpkgs update bots pick them up. As of 2026-10-15, `unstable` has hub 2.12.2 against upstream's 2.21.0 and CLI 1.2.16 against 1.3.1; only the IDE (2.5.5) is level. The hub, the main reason to have this at all, is the furthest behind.

So all three come from the [`jacopone/antigravity-nix`](https://github.com/jacopone/antigravity-nix) flake input, which pins the upstream tarballs in `artifacts/versions.json` and bumps them from CI roughly three times a week. It is taken as a **plain source tree** (`flake = false`): [`pkgs/default.nix`](../pkgs/default.nix) `callPackage`s its package files directly with this repo's own `unstable` nixpkgs, so its nixpkgs and flake-utils inputs would only bloat `flake.lock` without being used.

That input is built against `unstable` for two reasons: it's the nixpkgs upstream develops and CI-tests against, and it's the only package set here with `allowUnfree` — every Antigravity artifact is an unfree binary, and the GUI packages reference `google-chrome`.

**Updating is `nix flake update antigravity-nix`.** These packages deliberately carry no `passthru.updateScript`, so `scripts/update-packages.sh` does not (and should not) list them — the version pin lives in the input, exactly like `pkgs.local.slack` tracking `unstable`.

Once nixpkgs keeps pace — the hub in particular — the honest simplification is to drop the input and go back to `pkgs.unstable.antigravity-*`. Check the build options below against nixpkgs' packages before switching: they are different derivations, not this input's with other defaults.

## Build options

Both GUI packages are the same upstream derivation with a different `appType`, and both are built with two non-default arguments:

- **`useFHS = false`.** The upstream default runs the app inside a `buildFHSEnv` bubblewrap sandbox, which sets the kernel's *no new privileges* flag — that breaks `sudo` in the integrated terminal. The non-FHS variant patchelfs the bundled binaries instead, which is also how every other Electron app in this config is built.
- **`useUserProfile = false`.** (Upstream's name for what was `useSystemChromeProfile`, which still works but warns on every evaluation.) The default points the app's browser agent at the real Chrome profile (`--user-data-dir=$HOME/.config/google-chrome --profile-directory=Default`) so it inherits logins and extensions. Off, it gets its own profile.

Note that turning the profile sharing off does **not** drop the `google-chrome` dependency: the wrapper still sets `CHROME_BIN`/`CHROME_PATH` to a shim that prefers a system-installed `google-chrome-stable` and falls back to the store one. On `x86_64` that adds ~435 MiB to the closure (`aarch64-linux` uses `chromium` instead, upstream's choice). Passing `google-chrome` a substitute would have to provide a `bin/google-chrome-stable`, since the shim hardcodes that name.

## The IDE keyring flag

On Linux the IDE stores credentials in the desktop keyring, and Electron's autodetection doesn't reliably find it outside a GNOME session, so it needs `--password-store=gnome-libsecret` (the same flag this config passes to VS Code). The local package takes no `commandLineArgs` argument the way nixpkgs' Electron packages do, so the module adds the flag in a `postFixup` that wraps the wrapper upstream already installed. The resulting chain is `bin/antigravity-ide` → `.antigravity-ide-wrapped` → `launcher.sh` → the real binary, and the flag lands after upstream's own `--user-data-dir`.

## Darwin

**Antigravity is not installed on macOS at all** — it isn't used there, so `dedsm.antigravity.enable` is set in `users/david/nixos.nix` rather than `shared.nix`. morgoth previously carried the nixpkgs `antigravity-ide` and `antigravity-cli`; both are gone from its closure.

If that ever changes, note that the input's macOS derivations are marked experimental and untested upstream, and unpack the DMG into `$out/Applications` only — no `antigravity-ide` or `antigravity` on `PATH` — so flipping the toggle on a Darwin host is not by itself enough.
