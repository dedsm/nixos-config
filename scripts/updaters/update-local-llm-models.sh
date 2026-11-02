#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODELS_FILE="$REPO_DIR/modules/nixos/local-llm/models.json"

# Each model in models.json is pinned to a Hugging Face commit and the file's
# hash. This moves every pin to the repo's newest commit, and only prefetches
# when that commit is new, because a model can be many gigabytes. A new commit
# doesn't always change the file; the hash then stays the same and the store
# path with it.
for name in $(jq -r 'keys[]' "$MODELS_FILE"); do
  repo="$(jq -r --arg n "$name" '.[$n].repo' "$MODELS_FILE")"
  file="$(jq -r --arg n "$name" '.[$n].file' "$MODELS_FILE")"
  current="$(jq -r --arg n "$name" '.[$n].rev' "$MODELS_FILE")"
  latest="$(curl -fsSL "https://huggingface.co/api/models/$repo" | jq -er .sha)"

  if [ "$latest" = "$current" ]; then
    echo "$name: already at $latest"
    continue
  fi

  echo "$name: fetching $repo/$file at $latest..."
  hash="$(nix store prefetch-file --json --name "$file" \
    "https://huggingface.co/$repo/resolve/$latest/$file" | jq -er .hash)"

  updated="$(jq --arg n "$name" --arg rev "$latest" --arg hash "$hash" \
    '.[$n].rev = $rev | .[$n].hash = $hash' "$MODELS_FILE")"
  printf '%s\n' "$updated" >"$MODELS_FILE"
  echo "$name: pinned to $latest ($hash)"
done
