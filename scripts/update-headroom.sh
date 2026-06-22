#!/usr/bin/env bash
# Update the pinned Headroom version + wheel hashes in pkgs/headroom/version.json.
#
# Usage: scripts/update-headroom.sh [VERSION]
#   VERSION  optional, e.g. 0.27.0 — defaults to the latest on PyPI.
#
# Headroom is installed from its prebuilt abi3 wheels; this pulls the per-platform
# wheel URL + sha256 straight from the PyPI JSON API (no build needed).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_DIR/pkgs/headroom/version.json"

VERSION="${1:-$(curl -fsSL https://pypi.org/pypi/headroom-ai/json | jq -r '.info.version')}"
echo "Fetching wheels for headroom-ai v${VERSION}..."

JSON="$(curl -fsSL "https://pypi.org/pypi/headroom-ai/${VERSION}/json")"

# Pick the wheel whose filename matches a regex; print "url sha256".
wheel() {
  jq -r --arg re "$1" '.urls[] | select(.filename | test($re)) | "\(.url) \(.digests.sha256)"' <<<"$JSON"
}

read -r darwin_url darwin_sha < <(wheel 'macosx.*arm64\.whl$')
read -r linux_url linux_sha < <(wheel 'manylinux.*x86_64\.whl$')

for pair in "darwin:$darwin_url" "linux:$linux_url"; do
  [ -n "${pair#*:}" ] || { echo "error: missing ${pair%%:*} wheel for v${VERSION}" >&2; exit 1; }
done

cat > "$VERSION_FILE" <<EOF
{
  "version": "$VERSION",
  "platforms": {
    "aarch64-darwin": {
      "url": "$darwin_url",
      "sha256": "$darwin_sha"
    },
    "x86_64-linux": {
      "url": "$linux_url",
      "sha256": "$linux_sha"
    }
  }
}
EOF

echo "Updated $VERSION_FILE to v${VERSION}"
