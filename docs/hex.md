# Hex

[Hex](https://github.com/anomalyco/hex) is local voice dictation: speak, and the transcript is
pasted into the focused window. Speech is transcribed on this machine by a downloaded model.

It is not in nixpkgs (`pkgs.hex` is an unrelated hexdump tool). It comes from the Hex project's own
flake, whose Home Manager module `modules/common` registers for every user. `dedsm.hex.enable`
(`modules/home/hex`) turns it on, and only manwe sets it: the flake packages `x86_64-linux` only.

## Keys

| Key | Action |
| --- | --- |
| `Super+D` | `hex dictation toggle`: start recording, press again to transcribe and paste |
| `Super+Shift+D` | `hex paste-last`: paste the last dictation again |

Caps Lock is Super on this layout, so `Caps+D` works too.

**The keys live in the Hyprland config, not in Hex.** Hyprland's GlobalShortcuts portal registers
Hex's shortcuts without a key, so the shortcut recorded in Hex's Settings does nothing here, and
`programs.hex.shortcut` is left unset.

**Toggle, not hold.** Hold-to-talk depends on a release event, and Hex's docs record Hyprland's Lua
binds dropping it when the modifier comes up before the key (fixed in 0.57; this machine ran 0.55
when this was written). Toggle needs no release.

**Let go of Super quickly.** Hyprland adds every modifier still held to Hex's paste. After a `hex`
command Hex waits 250 ms and then pastes, so Super held past that plus the transcription turns
`Ctrl+Shift+V` into `Super+Ctrl+Shift+V`, and the app doesn't paste. The text is still on the
clipboard, and `Super+Shift+D` pastes it again.

## Settings

Set in `modules/home/hex`. `hex settings apply` merges them on every activation. Anything not
declared stays editable in Hex's window, and `settings.json` stays writable. An unknown key or a bad
value makes the whole apply fail with a warning, without failing the switch, so check the activation
output after adding one.

- **`model = "parakeet_v3"`**: 25 languages, detected from the audio, 740 MB. Hex's default,
  Parakeet Unified English, is English-only but more accurate on English and streams. Hex's catalogue
  gives 1.60% against 1.94% word error on its English benchmark.
- **`paste_with_shift = true`**: Hex sends `Ctrl+Shift+V` instead of `Ctrl+V`, because foot pastes on
  `Ctrl+Shift+V` and passes `Ctrl+V` through to the program inside. Hex has one paste key for every
  app, so a target that doesn't bind `Ctrl+Shift+V` won't paste. The text is on the clipboard for
  500 ms before Hex restores the previous contents, so use `Super+Shift+D` or `hex paste-last` after
  focusing somewhere that does paste.
- **`release_microphone_while_idle = true`**: by default the mic stays open for the whole session so
  dictation can start instantly with pre-roll. That holds the audio device awake and keeps a Bluetooth
  headset on its call profile. The cost is a slower start and no pre-roll, so wait a moment before
  speaking.

## Models

`installModel = true` adds the `hex-model` user service, which runs `hex model install` at login,
once `network-online.target` is up or after two minutes. It retries every 60 seconds on failure. A
switch never waits for it. Models go to `~/.local/share/hex/models`, not the Nix store, and Hex checks
them against the SHA-256 pinned in its source.

`NetworkManager-wait-online` is masked on manwe, so `network-online.target` doesn't actually wait for
a connection: offline, the first attempt fails and the 60-second retry takes over.

**Changing `model`** doesn't change the service's unit, so a switch shouldn't restart it. Download the
new model with `systemctl --user start hex-model`, or at the next login. Old models stay on disk until
removed with `hex model` or in Settings.

**The first enable can select the wrong model.** On manwe's first switch `hex-model` started
just before `hexSettings` applied the declared settings, and it downloaded Hex's default. Hex
then ended up on Parakeet Unified English instead of v3, either from that or from its one-time
`streaming-english-model` migration, which moves English dictation to that model once it is
installed. The migration is recorded as done in `settings.json`, so this was fixed once with
`hex model install parakeet_v3`. Check `hex settings get transcription.model` on a new machine.

Nix could own the files instead, with `fetchurl` and `xdg.dataFile` symlinks into the models directory.
That isn't done here: each model would add 740 MB to the store, the pins would have to track Hex's on
every update, and it gains little integrity over Hex's own check.

## Transcribing speaker audio

Pick **Speakers (loopback)** in General › Microphone, and dictation transcribes what the default output
plays instead of your voice. Pick your microphone again to go back: the selection is global, so Hex
hears one or the other. Meetings, the feature meant for system audio, is switched off outside macOS even
though the source has a PipeWire capture for it, so `modules/home/hex` builds this from two parts:

- **`hex-speakers-loopback`**, a user service running `pw-loopback`, creates the PipeWire source
  `hex_speakers` from the default output's monitor. It follows the default output, and being passive
  it doesn't keep that output awake. A service rather than a `pipewire.conf.d` drop-in, so a switch
  starts it without restarting PipeWire and interrupting audio.
- **`~/.asoundrc`** defines an ALSA device pointing at that source. Hex's list holds ALSA devices only
  and never shows PipeWire nodes, so without this the source exists but can't be selected.

The monitor doesn't depend on the speaker volume or mute (see [`granola.md`](./granola.md)), so this
works with the speakers muted.

To transcribe a recording instead, without changing the selection:

```sh
pw-record -P stream.capture.sink=true --rate 16000 --channels 1 --format s16 speakers.wav  # Ctrl+C to stop
hex model transcribe speakers.wav
```

For live text, Hex's documented `/streams` API accepts 16 kHz mono from any source, but nothing here
implements a client for it.

## Dux Shell

Hex has no Dux Shell integration, and the plugin registry has no plugin for it. It appears in the bar
through the `systemTray` widget, as a StatusNotifierItem, and draws its own recording overlay over
layer-shell. The registry's `whisperer` plugin is a separate dictation tool built on whisper.cpp, not a
front end for Hex.

## Session environment

The `hex` unit needs `WAYLAND_DISPLAY`, and Hex's docs tell Hyprland users to import it by hand. uwsm
already does that here, and it provides the `graphical-session.target` the unit starts with, so
nothing is added. Without a display in its environment, the overlay can fail (Hex issue #756).

Debugging: `systemctl --user status hex.service`, `journalctl --user -u hex.service`,
`journalctl --user -u hex-model`, `hex status --json`.

## Updating

The input is pinned to a release tag (`github:anomalyco/hex/v3.2.0`) because the default branch is
`dev`, Hex's newest development builds. `nix flake update` therefore won't move it: change the tag in
`flake.nix`, then run `nix flake update hex`. Hex's in-app updater doesn't touch a Nix install.

The input follows this repo's `unstable`, not `nixpkgs`, because Hex needs a newer Rust than 26.05's
1.95 (v3.1.2 needed 1.97). Don't leave it on Hex's own pinned nixpkgs: Hex's docs warn that it can then end up on an older
glibc than the system's graphics drivers need, find no Vulkan adapter, and not open its window. `unstable`
avoids that because its glibc is at least as new as the one the drivers are built against.

**Building takes a while.** Hex has no binary cache, so it compiles from source, its tests included:
expect well over 10 minutes on manwe. Updating `unstable` usually changes the derivation, so it
usually means another rebuild, not only bumping Hex's tag.

## Privacy

Audio stays on this machine. Text can leave it only through Hex's optional OpenCode rewrite, which isn't
configured here, or through a custom transform in `~/.config/hex/hex.config.ts`, which this repo doesn't
manage. Since v3.2.0 a transform can use `fetch` and `node:child_process`, but only once its config is
allowed at a trust prompt, which asks again after any edit to it. Three things persist locally: History (7 days by default), Hex's diagnostic logs (currently unbounded, and not stopped by turning History off),
and transcripts in the Dux Shell clipboard history, because Hex pastes through the clipboard.
