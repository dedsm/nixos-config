# Google Antigravity

Module: [`modules/common/users/common/antigravity/`](../modules/common/users/common/antigravity/) · toggle: `antigravity.enable` (on in `davidNixos`, off in `davidShared` — this is Linux-only, see [Darwin](#darwin)), with per-component sub-toggles `antigravity.hub.enable`, `antigravity.ide.enable`, `antigravity.cli.enable`, all on when the module is.

Antigravity 2.0 split the product into three separately-shipped artifacts, and this config installs all three:

| Component | Binary | Package |
|---|---|---|
| Hub — the 2.0 agent-orchestration app | `antigravity` | `pkgs.local.antigravity-hub` |
| IDE — the legacy 1.x editor, still maintained | `antigravity-ide` | `pkgs.local.antigravity-ide` |
| CLI | `agy` | `pkgs.local.antigravity-cli` |

The three binaries don't collide, so all of them can be on `PATH` at once.

## Why not nixpkgs

nixpkgs has `antigravity-ide` and `antigravity-cli` but **no hub package** — that is still an open PR ([NixOS/nixpkgs#524225](https://github.com/NixOS/nixpkgs/pull/524225)), so it isn't in `unstable` and can't just be enabled. The IDE and CLI that *are* in nixpkgs also trail upstream, because Google ships new tarballs faster than the nixpkgs update bots pick them up.

So all three come from the [`jacopone/antigravity-nix`](https://github.com/jacopone/antigravity-nix) flake input, which pins the upstream tarballs in `artifacts/versions.json` and bumps them from CI roughly three times a week. It is taken as a **plain source tree** (`flake = false`): [`pkgs/default.nix`](../pkgs/default.nix) `callPackage`s its package files directly with this repo's own `unstable` nixpkgs, so its nixpkgs and flake-utils inputs would only bloat `flake.lock` without being used.

That input is built against `unstable` for two reasons: it's the nixpkgs upstream develops and CI-tests against, and it's the only package set here with `allowUnfree` — every Antigravity artifact is an unfree binary, and the GUI packages reference `google-chrome`.

**Updating is `nix flake update antigravity-nix`.** These packages deliberately carry no `passthru.updateScript`, so `scripts/update-packages.sh` does not (and should not) list them — the version pin lives in the input, exactly like `pkgs.local.slack` tracking `unstable`.

If the nixpkgs PR lands and nixpkgs starts keeping pace, the honest simplification is to drop the input and go back to `pkgs.unstable.antigravity-*`.

## Build options

Both GUI packages are the same upstream derivation with a different `appType`, and both are built with two non-default arguments:

- **`useFHS = false`.** The upstream default runs the app inside a `buildFHSEnv` bubblewrap sandbox, which sets the kernel's *no new privileges* flag — that breaks `sudo` in the integrated terminal. The non-FHS variant patchelfs the bundled binaries instead, which is also how every other Electron app in this config is built.
- **`useSystemChromeProfile = false`.** The default points the app's browser agent at the real Chrome profile (`--user-data-dir=$HOME/.config/google-chrome --profile-directory=Default`) so it inherits logins and extensions. Off, it gets its own profile.

Note that turning the profile sharing off does **not** drop the `google-chrome` dependency: the wrapper still sets `CHROME_BIN`/`CHROME_PATH` to a shim that prefers a system-installed `google-chrome-stable` and falls back to the store one. On `x86_64` that adds ~435 MiB to the closure (`aarch64-linux` uses `chromium` instead, upstream's choice). Passing `google-chrome` a substitute would have to provide a `bin/google-chrome-stable`, since the shim hardcodes that name.

## The IDE keyring flag

On Linux the IDE stores credentials in the desktop keyring, and Electron's autodetection doesn't reliably find it outside a GNOME session, so it needs `--password-store=gnome-libsecret` (the same flag this config passes to VS Code). The local package takes no `commandLineArgs` argument the way nixpkgs' Electron packages do, so the module adds the flag in a `postFixup` that wraps the wrapper upstream already installed. The resulting chain is `bin/antigravity-ide` → `.antigravity-ide-wrapped` → `launcher.sh` → the real binary, and the flag lands after upstream's own `--user-data-dir`.

## Darwin

**Antigravity is not installed on macOS at all** — it isn't used there, so `antigravity.enable` is set in `davidNixos` rather than `davidShared`. morgoth previously carried the nixpkgs `antigravity-ide` and `antigravity-cli`; both are gone from its closure.

If that ever changes, note that the input's macOS derivations are marked experimental and untested upstream, and unpack the DMG into `$out/Applications` only — no `antigravity-ide` or `antigravity` on `PATH` — so flipping the toggle on a Darwin host is not by itself enough.
