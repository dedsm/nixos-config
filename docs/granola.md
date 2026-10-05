# Granola

Package: [`pkgs/granola/`](../pkgs/granola/) · installed in `manweUserConfig`'s package list (`pkgs.local.granola`), so only manwe gets it. It is `x86_64-linux` only.

[Granola](https://www.granola.ai) (an AI notepad for meetings) ships for macOS and Windows only. It is an Electron app, though, so the macOS build carries all of its JavaScript, and that runs on nixpkgs' Linux Electron once a few things are fixed. The recipe comes from [tirtha4/Granola-for-Linux](https://github.com/tirtha4/Granola-for-Linux), which does the same thing as a shell script that installs into `~/Applications`. Here it is a derivation, built the same way as the nixpkgs Electron apps that run on the shared `electron` (signal-desktop, ente-desktop, goose-desktop). Nixpkgs has no Granola package.

## Source

The source is the **macOS auto-update payload**, not the `.dmg` from the website. The in-app updater reads `https://api.granola.ai/v1/check-for-update/latest-mac.yml`, which points at a versioned universal `.zip` on CloudFront and gives its sha512. That sha512 is used as the `fetchurl` hash verbatim. The `.zip` has three advantages over the `.dmg`:

- it has a stable, versioned URL;
- it comes with a published hash;
- it unpacks with `unzip`, where the `.dmg` is LZFSE-compressed and needs a recent `7zz`.

Only `app.asar`, `app.asar.unpacked/`, `icons/` and Electron's `Info.plist` are extracted. The rest is the macOS runtime.

## What the build changes

1. **Plain directory instead of an asar.** `asar extract` folds `app.asar.unpacked` back in, and the wrapper runs `electron <dir>`. This turns every patch below into an ordinary text edit. An in-place asar patch would have to keep each file's byte length unchanged.
2. **Platform label.** `api.granola.ai` answers 500 to any request carrying `platform=linux`, sign-in included. The app maps `darwin`→`macOS` and `win32`→`Windows` and passes anything else through unchanged. The build rewrites that fallback (`?`Windows`:process.platform` and `?`Windows`:window.electron.platform`) so the fallback branch also says `Windows`. Only the label sent to the API changes; `process.platform` is still `linux`, so no Windows-only code runs. The build fails if it finds nothing to rewrite.
3. **Packaged mode.** nixpkgs' launcher binary is named `electron`, so Electron reports `app.isPackaged = false`, and Granola then runs in its **dev mode**: it registers `granola-dev://` instead of `granola://` for the sign-in callback, opens a remote-debugging port and uses a mock keychain. The wrapper sets `ELECTRON_FORCE_IS_PACKAGED=1`, as signal-desktop and goose-desktop do. (tirtha4's script runs Electron's stock `electron` binary, so it gets dev mode.)
4. **`process.resourcesPath`.** In packaged mode the app looks up its tray icons and helpers under `process.resourcesPath`, which would be nixpkgs' Electron's own `resources/`. Every use in `dist-electron/` is rewritten to `$out/share/granola/resources`, which holds `app/` and `icons/` (the same approach as ente-desktop).
5. **The SQLite native module.** Granola ships a **patched fork** of `better-sqlite3-multiple-ciphers` (encrypted local DB). It adds an `updateHook()` that the renderer calls on startup, so a stock build gives a window that dies with `r.updateHook is not a function`. The fork's full C++ source is in the bundle; only `binding.gyp` is missing, and that comes from the matching npm release (`sqliteCipher` in the package). The build compares the bundled version with that pin and fails on a mismatch.
   - The module is compiled against **`electron.headers`**, not Node's. nixpkgs' `node-gyp` package is a wrapper that *force-sets* `npm_config_nodedir` to its own nodejs. That overrides both the usual `npm_config_nodedir=${electron.headers}` convention and `--nodedir`, so the build calls node-gyp's JS entry point directly. Through the wrapper, the module is built against Node 24's headers. Those ship a stock `sqlite3.h` that shadows the cipher-enabled one (`sqlite3_key` is undeclared), and even if it compiled, it would have Node's ABI rather than Electron's.
   - The compile is effectively serial: the sqlite3 amalgamation and `better_sqlite3.cpp` are one translation unit each, and the second depends on the first, so `--jobs` buys nothing.
6. **`drag.node`.** `electron-click-drag-plugin` ships a prebuilt `linux-x64/drag.node` (N-API, so no ABI concern), and the main process `require`s it at startup. It links `libstdc++`, which `autoPatchelfHook` adds an RPATH for. **stdenv's patchelf (0.15) corrupts this file**: it then segfaults in its own initializers on `dlopen`, taking the app down with it. `patchelfUnstable` (0.18) patches it correctly and is listed next to `autoPatchelfHook` so the hook uses it, the same fix firefox-bin and floorp-bin carry.

`installCheckPhase` runs tirtha4's smoke test under `ELECTRON_RUN_AS_NODE`: it loads `drag.node` and `registry-js`, then opens an `sqlcipher`-encrypted database and checks that `updateHook()` fires.

## Electron version

The native module only matches Electron's ABI within one major version. `pkgs/default.nix` passes `unstablePkgs.electron_44` (Granola 7.626.1 ships Electron 44.4.2), and the build reads the bundled Electron version and fails with the `electron_N` to switch to when the majors differ. The package comes from `unstable` because that package set has `allowUnfree` and Granola is proprietary (`meta.license = unfree`).

## Desktop integration

The desktop entry is `granola.desktop`, with `MimeType=x-scheme-handler/granola` so that the browser's sign-in redirect reopens the app. The window's Wayland app id is `granola`. Wayland flags are the same as `pkgs/slack`: `--ozone-platform=wayland` plus `WaylandWindowDecorations` and `--enable-wayland-ime`, behind nixpkgs' `NIXOS_OZONE_WL` gate (the hyprland module sets it). App data lives in `~/.config/Granola`.

## System audio (the other side of a call)

This works, unpatched, even though tirtha4's README lists it as limited. The macOS build captures through Core Audio. On Linux the renderer calls `getDisplayMedia({ audio, video: false })`, and the main process's `setDisplayMediaRequestHandler` falls through to the reply it gives macOS 14+, `audio: { id: 'loopbackAllDevices' }`. On Linux, Electron 44's PulseAudio backend opens the **monitor of the default output** for that (seen in `pactl list source-outputs`), just as it does for `'loopback'`.

It was tested with a minimal Electron 44 app using Granola's exact handler reply. A 0.05-amplitude tone played from another process (`pw-play`) read back at a 0.04999 peak. It was then tested in Granola itself: a YouTube video in Firefox was transcribed, with the speakers muted as well as unmuted. Microphone capture is a separate stream. Two things to know:

- **The monitor's own volume matters; the speaker volume and mute don't.** The "Monitor of …" source has a volume of its own (pavucontrol → Input Devices → Show: Monitors; `pactl get-source-volume @DEFAULT_SINK@.monitor`), and Granola hears the monitor at that level. Once it sat at 8% (−66 dB): Granola caught only a faint trace, and every app reading the monitor saw near-silence. Nothing in WirePlumber's saved state stores that volume, and Granola left it alone across a restart and a full recording, so the 8% probably came from another client. If capture goes quiet, check it first, and fix it with `pactl set-source-volume @DEFAULT_SINK@.monitor 100%`.
- **It records whichever output is the default.** When call audio goes to a different device (say, a headset that isn't the default), set that device as the default before recording.

## What doesn't work

These limitations come with tirtha4's approach:

- **Apple Calendar** (EventKit). Google and Microsoft calendars work, since those are server-side.
- **Global hotkeys** (`keyspy` ships only a macOS key server).
- **The Google Meet consent helper**: the app logs `meet-consent-enable-failed` at startup, because `native-host/meet-consent-host` is a macOS binary that isn't packaged.
- **In-app updates.** With no `APPIMAGE` set, electron-updater's Linux updater stays inactive. Updates come from the updater below.

## Updating

`scripts/update-packages.sh granola` runs `passthru.updateScript` (`pkgs/granola/update.sh`). It:

1. reads `latest-mac.yml` and rewrites `version` and the zip's `hash`;
2. fetches the new zip (which leaves it in the store for the rebuild);
3. re-pins `sqliteCipher` to the `better-sqlite3-multiple-ciphers` version the zip bundles, taking the hash from the npm registry's `dist.integrity`;
4. exits non-zero, naming the `electron_N` to switch to in `pkgs/default.nix`, if the bundled Electron major has changed.

If an update breaks the build at the platform or `resourcesPath` patch, Granola's bundler output has changed shape. Check what the rewrite targets still look like in `dist-app/` and `dist-electron/main/index.js`.
