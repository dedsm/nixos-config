# Local model server

`dedsm.localLlm` (`modules/nixos/local-llm`) runs one OpenAI-compatible server for local models, for
anything on this machine to call. A request names a model, the server loads it if needed, and it is
freed again when idle. Only manwe enables it.

Hex's [dictation cleanup](./hex.md#cleanup) is the first client, using both models listed so far: `cleanup`
(Spokenly's Cleanup 1, plain-text prompts) and `gemma` (Gemma 4 E4B, chat).

## How it fits together

- **The service** is nixpkgs' `services.llama-cpp`: `llama-server` from llama.cpp in its router mode,
  at `http://127.0.0.1:8012`, as a sandboxed system service with a dynamic user.
- **The models** are listed in `modules/nixos/local-llm/models.json`. Nix downloads each one into the
  store and the module generates the server's preset file from the list.
- **The build** is `pkgs.unstable.llama-cpp-vulkan`, so models run on the iGPU.

The server listens on loopback only, and that matters: `modules/nixos/core` turns the firewall off.

## Using a model

Name it in the `model` field. `/v1/chat/completions` and `/v1/completions` both work:

```bash
curl -s http://127.0.0.1:8012/v1/completions -H 'content-type: application/json' -d '{
  "model": "cleanup",
  "prompt": "text: um we should we should ship it\nout:",
  "temperature": 0,
  "max_tokens": 64
}' | jq -r '.choices[0].text'
```

`curl -s http://127.0.0.1:8012/models | jq` lists the models and whether each is loaded. A Claude Code
skill or a script can use this the same way, with no setup beyond knowing the model's name.

## Loading and unloading

A model loads on its first request. On the 890M, Cleanup 1 takes about 1 s to load and Gemma 4 E4B about
3.2 s, or about 5 s with its file out of the disk cache.

- **`--sleep-idle-seconds 14400`** frees a model after 4 hours unused. It wakes on the next request, which
  takes about as long as loading. In a test with a 15-second limit, status went to `sleeping` and GPU memory
  went back to where it started.
- **`--models-max 2`** caps how many models are loaded at once. The router frees one to make room for
  another. Hex's cleanup uses both, so a third model would make them take turns, each reload costing the times
  above. This hasn't been tested yet, and raising the limit would avoid it.

Both models together use about 6.6 GiB of GPU memory, which on the 890M is shared system RAM, plus under 500 MiB
in the server's processes. Check `mem_info_gtt_used` under `/sys/class/drm/card*/device/` to see it.

`llama-swap` (`services.llama-swap`) is the alternative: a proxy with a separate idle time for each
model. Consider it if big models need different limits, since the router's idle time covers them all.

## Adding a model

Add an entry to `models.json`, with `rev` and `hash` left empty:

```json
"coder": {
  "repo": "someone/some-model-GGUF",
  "file": "some-model-Q4_K_M.gguf",
  "rev": "",
  "hash": "",
  "preset": { "ctx-size": 8192, "n-gpu-layers": 99, "parallel": 1, "jinja": "on" }
}
```

Then run `scripts/update-packages.sh local-llm-models`, which fills in the pin, and rebuild. The entry's
name is the name requests use. `preset` takes `llama-server`'s long option names without the dashes.
A chat model needs `jinja`; Cleanup 1 takes a plain-text prompt and doesn't. Both current models set
`"spec-type": "ngram-simple"`: speculative decoding that drafts tokens from n-grams already in the context instead of
from a draft model. It costs nothing measurable on short requests and pays off when the answer repeats the prompt,
which is all Hex's cleanup does — Gemma's pass on long dictations got about 5× faster, with the same output token
for token (greedy sampling).

Check a model's licence before adding it. It isn't subject to `lib/pkgs.nix`'s unfree allowlist, because
it's fetched rather than packaged.

## Updating models

`scripts/update-packages.sh local-llm-models` (or a bare `scripts/update-packages.sh`) moves each model
to its repo's newest Hugging Face commit and records the file's hash. It only downloads when the commit
changed. Review with `git diff` and rebuild, like any other pin.

A model's replacement can behave differently even under the same name, so check its clients after an
update. Old versions leave the store with the normal garbage collection.

## Why models are in the Nix store

Pinning by commit and hash means a rebuild can't silently change what a client gets, and removing an
entry reclaims the space. The cost is that a large model has to fit in the store, and it stays there
until GC after being replaced.

Hex makes the opposite choice for its speech models ([why](./hex.md#models)), because Hex already pins
and verifies those itself. Nothing else pins these.

The module's own alternative, `hf-repo` and `hf-file` in the preset, would download at runtime with no
pin, so it isn't used.

## The service's environment

The module's sandbox hides `/home`, and the router failed to start in testing when it couldn't check for
a Hugging Face cache under `$HOME`. So `HOME` is set to the module's state directory, and `XDG_CACHE_HOME`
to its cache directory for Mesa's shader cache. A `Permission denied` naming a `huggingface` path means
this has been lost.

The sandbox leaves devices open, and `/dev/dri/renderD128` is world-accessible, so the dynamic user needs
no extra group for the GPU.

## Debugging

```bash
systemctl status llama-cpp
journalctl -u llama-cpp -e
curl -s http://127.0.0.1:8012/models | jq
```

The module restarts a crashed server after 300 seconds, not immediately.
