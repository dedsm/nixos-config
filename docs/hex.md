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
| `Super+A` | `hex annotate toggle`: start or stop an [Annotate](#annotate) recording |
| `Super+Shift+A` | `hex annotate draw`: turn its pen on or off, starting a recording if none runs |

Caps Lock is Super on this layout, so `Caps+D` works too.

**The keys live in the Hyprland config, not in Hex.** Hyprland's GlobalShortcuts portal registers
Hex's shortcuts without a key, so the shortcut recorded in Hex's Settings does nothing here, and
`programs.hex.shortcut` is left unset.

**Toggle, not hold.** Hold-to-talk depends on a release event, and Hex's docs record Hyprland's Lua
binds dropping it when the modifier comes up before the key. That's fixed in 0.57, which this machine
now runs, but hold hasn't been retried here. Toggle needs no release.

**Let go of Super quickly.** Hyprland adds every modifier still held to Hex's paste. After a `hex`
command Hex waits 250 ms and then pastes, so Super held past that plus the transcription turns
`Ctrl+Shift+V` into `Super+Ctrl+Shift+V`, and the app doesn't paste. The text is still on the
clipboard, and `Super+Shift+D` pastes it again.

## Settings

Set in `modules/home/hex`. `hex settings apply` merges them on every activation. Anything not
declared stays editable in Hex's window, and `settings.json` stays writable. An unknown key or a bad
value makes the whole apply fail with a warning, without failing the switch, so check the activation
output after adding one.

- **`model = "parakeet_unified_en"`**: Hex's default, 730 MB, English only. It streams, which
  [live text](#live-text) needs, and a streamed dictation finishes in about 200 ms after the keypress
  instead of being transcribed whole (32 s for a 107 s clip on Parakeet v3). Of the catalogue's two
  streaming models it is the more accurate: 1.60% word error on Hex's English benchmark, against 3.05%
  for Nemotron 3.5 ASR. Nemotron is the one to pick if dictation needs other languages (27), and
  Parakeet v3 (25 languages, 1.94%) if those matter more than live text.
- **`paste_with_shift = true`**: Hex sends `Ctrl+Shift+V` instead of `Ctrl+V`, because foot pastes on
  `Ctrl+Shift+V` and passes `Ctrl+V` through to the program inside. Hex has one paste key for every
  app, so a target that doesn't bind `Ctrl+Shift+V` won't paste. The text is on the clipboard for
  500 ms before Hex restores the previous contents, so use `Super+Shift+D` or `hex paste-last` after
  focusing somewhere that does paste.
- **`release_microphone_while_idle = true`**: by default the mic stays open for the whole session so
  dictation can start instantly with pre-roll. That holds the audio device awake and keeps a Bluetooth
  headset on its call profile. The cost is a slower start and no pre-roll, so wait a moment before
  speaking.

## Live text

The Labs toggle `live-text` (`hex labs on live-text`) shows provisional words beside the overlay while
recording. It isn't declared here, so it stays a choice made in Hex and is kept in `settings.json`.

The toggle alone does nothing unless the selected model streams: with an offline model it stays on, no
words appear, and the log shows no error. The model picker tags the ones that can with "Streams". To
check, `hex logs --process` should show `source="stream"` and `finished live stream` with a non-zero
`partials` count for each dictation. `source="offline"` means no stream ran. On manwe the text changed
every two seconds or so. The text shown is never pasted: the final transcript replaces it.

## Cleanup

`dedsm.hex.cleanup.enable` removes fillers, repeats and false starts from each dictation and fixes misheard
technical names, on this machine. It needs the [local model server](./local-llm.md) (`dedsm.localLlm`), and
evaluation fails without it. A dictation goes through:

1. **Hex's Labs toggles**, declared on: `spoken-formatting` turns "open quote", "close quote" and "new line"
   into characters, and `filler-words` removes "um" and "uh".
2. **Cleanup 1**, a small model trained for dictation: fillers, repeats, spoken corrections like "no wait", and
   punctuation. It has no instructions to tune, only `text: ...` and `out:`.
3. **The fixed rules**: "flake dot nix" to `flake.nix`, "my underscore variable" to `my_variable`, a spoken path
   to `lib/pkgs.nix`, and repeats like "the the".
4. **Gemma 4 E4B**, with a prompt and a short term list, fixing only misheard names: "knicks OS" to NixOS.
5. **The fixed rules again**, in case Gemma undid them.

Steps 2 to 5 are the `cleanup` transform, `modules/home/hex/hex.config.ts`. Each line is handled separately, so a
spoken "new line" survives.

**Why two models.** Tested alone, Cleanup 1 was fast and good at fillers and punctuation but left names like
"knicks" alone, and Gemma fixed names but left long sentences unpunctuated. Why the rules run before Gemma as well:
it rewrote `my underscore variable` into `my_ variable` otherwise.

**The term list is not a set of replacements.** It was: with `flake.nix` and `llama-server` on it, Gemma turned
"knicks flake update" into `flake.nix flake update` and "Lama service" into `llama-server`. So the prompt now says
never to swap a name for a different one, and the list holds plain names. Keep it short and general. It goes in
every request, and a word that keeps coming out wrong is better fixed by the prompt than by a rule per word.

**Timing, on the 890M.** A dictation of a sentence or two takes about 1.4 s after transcription when both models
are loaded, 0.7 s to 3.5 s across the samples tried. With the models unloaded, or waking from idle sleep, it's about
5.5 s, and about 7.3 s with Gemma also out of the disk cache. Those happen once, on the first dictation after
[4 hours idle](./local-llm.md#loading-and-unloading).

**It can fail safely.** Every pass is optional. If one fails, the text carries on without it, with a log line
starting `cleanup:`. An answer whose length is implausible is discarded, which Cleanup 1 needs on very short input:
"um we need to to fix it" came back empty. Past 25 s the remaining passes are skipped, so Hex's 30-second transform
limit doesn't throw away work already done.

**It's still models.** "iGPU" comes back as "GPU" and "home manager" as "HomeManager", both from Cleanup 1. Spelling
something out letter by letter doesn't survive Gemma. Live text isn't cleaned: the overlay shows raw words, and the
pasted text is the cleaned version.

**Streaming wouldn't help.** Hex's `fetch` reads a response whole, and a transform returns one finished string. The
paste has to wait for the final text anyway.

**The trust prompt.** A transform that uses `fetch` needs one approval in Hex's Output pane, pinned to a hash of the
config. Until then both models are skipped, while the fixed rules still run. Changing `hex.config.ts` in any way asks
again. Nix can't answer it, by design: a config can't approve itself.

**Nix owns these.** Activation copies `hex.config.ts` over `~/.config/hex/hex.config.ts`, so add transforms in the
repo. It's a copy and not a `home.file` link because Hex's watcher skips symlinks, and Hex refreshes the files beside
it, so the folder has to stay writable. `dictation_processing.default_mode` is declared whole, so corrections added
in the Output pane are lost on the next switch.

**Why not OpenCode.** Hex's OpenCode option is one call to a one-shot route per dictation, without an agent session,
so it would add a service and no passes. A transform can make as many calls as it likes.

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

**The selected model can drift on a first enable.** `hex-model` can start just before `hexSettings`
applies the declared settings, and so download Hex's default. Hex also has a one-time
`streaming-english-model` migration, which moves English dictation to Parakeet Unified English once it
is installed. Both now land on the declared model, but declaring a different one means checking
`hex settings get transcription.model` on a new machine.

`hex model use` only lasts until the next switch, because activation applies the declared model again.

Nix could own the files instead, with `fetchurl` and `xdg.dataFile` symlinks into the models directory.
That isn't done here: each model would add 730 MB to the store, the pins would have to track Hex's on
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

With **Speakers (loopback)** selected, [live text](#live-text) shows what the speakers are playing as it
plays. That still occupies dictation: Hex's documented `/streams` API accepts 16 kHz mono from any source
without touching the selection, but nothing here implements a client for it.

## Annotate

Hex's Annotate records the screen or a window with narration from Hex's microphone and ink drawn on top, and
writes a bundle for an agent: `recording.mp4`, keyframes, a contact sheet, `scrawl.json`, and a summary with the
transcript. It's on by default, and it isn't configured here beyond the keys above. It complements
[`dms-screencast`](./dms.md#screen-recording), which makes full-resolution videos to share. Annotate scales to
2560 px on the long edge, and its own overlay shows in the recording.

The bundle goes to the clipboard. Pasted into a terminal, it's the summary, which names the contact sheet. Hex can
also send it to a running OpenCode session, but OpenCode isn't installed here, so `capture.routing` is declared with
`sendCaptures = false`. Otherwise every capture ends by complaining that it can't reach OpenCode. The key is an
object set whole, so routing changed in Hex's window is lost on the next switch. `hex annotate list` and `hex annotate
show` read past captures, which keep their video for 7 days and the rest for 30.

Hex's default key, F9, belongs to Dux Shell here, and Hyprland's portal wouldn't honour a key set in Hex anyway, so the
keys are Hyprland binds. They're toggles because holding a key to draw needs a release event: with a Lua bind to
`hl.dsp.global` on Hyprland 0.55.4, releasing the key did nothing until the next tap.

Recording works on manwe from DMA-BUFs, apparently with VA-API (the file has no x264 marker, and the log names no encoder).

**Drawing is only partly right on v3.3.0.** Recording follows what's picked in the portal, but the pen doesn't, in three ways:

- **It stays on the monitor where the capture started**, at the top left, whatever was picked. Clicks elsewhere reach the app underneath, which looks like the pen not working. The workaround is to start the capture on the screen being shared.
- **It uses the wrong scale.** Rune takes a layer surface's scale from `wl_surface.preferred_buffer_scale`, an integer, so 1.5 and 1.33 become 2 and the pen's area shrinks: only the top-left 1128x752 of the 1692x1128 laptop screen works. Hex's fix for this ([#1001](https://github.com/anomalyco/hex/pull/1001)) takes the logical size from the portal's `size`, but xdph reports pixels there, so it does nothing here.
- **It stops at the bar**, because Rune's layer has an exclusive zone of 0. Strokes there don't reach Hex, and the clicks go to Dux Shell.

These are reported as [#999](https://github.com/anomalyco/hex/issues/999) (scale and bar) and [#1000](https://github.com/anomalyco/hex/issues/1000) (target). For screen picks all three have a fix that needs no Hyprland-specific code, tested on the laptop screen but not part of this repo: xdph 1.4.1 and later send the output's name as `mapping_id`, which finds its `wl_output` and its logical size from `xdg_output`, and a full-screen overlay can use an exclusive zone of -1. Nothing in the portal identifies a picked window, and xdph reports a stream's position as 0,0. The pen cursor never appears, because Rune maps custom cursors to the default shape on layer surfaces.

The stock portal picker, now only the [fallback](./share-picker.md), floats (`float-share-picker` in `modules/home/hyprland`). Tiled, it shrinks the windows beside it, so a window picked on that screen starts its stream at the wrong size.

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

The input is pinned to a release tag (`github:anomalyco/hex/v3.3.0`) because the default branch is
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
configured here, or through a custom transform. Since v3.2.0 a transform can use `fetch` and
`node:child_process`, but only once its config is allowed at a trust prompt, which asks again after any edit
to it. The one declared here calls only the [local model server](./local-llm.md), on loopback. Three things persist locally: History (7 days by default), Hex's diagnostic logs (currently unbounded, and not stopped by turning History off),
and transcripts in the Dux Shell clipboard history, because Hex pastes through the clipboard.
