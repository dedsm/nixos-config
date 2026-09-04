#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST_FILE="$REPO_DIR/modules/common/users/common/claude-code/manifest.zst.json"
BASE_URL="https://downloads.claude.ai/claude-code-releases"

# The pin is upstream's release manifest, stored verbatim and handed straight to
# nixpkgs' `claude-code` via its `manifest` argument. So updating is just
# refetching it — same thing nixpkgs' own update.sh does. Keeping zero
# transformation here is deliberate: nothing local to fall out of date when the
# manifest schema, URL layout or artifact format changes.
VERSION="${1:-$(curl -fsSL "$BASE_URL/latest")}"
echo "Fetching manifest for claude-code v${VERSION}..."

curl -fsSL "$BASE_URL/$VERSION/manifest.zst.json" --output "$MANIFEST_FILE"

echo "Updated $MANIFEST_FILE to v${VERSION}"
