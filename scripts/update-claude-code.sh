#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_DIR/modules/common/users/common/claude-code/version.json"
BASE_URL="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

# Get version: use argument, or fetch latest
VERSION="${1:-$(curl -fsSL "$BASE_URL/latest")}"
echo "Fetching manifest for claude-code v${VERSION}..."

MANIFEST=$(curl -fsSL "$BASE_URL/$VERSION/manifest.json")

# Extract hex checksums for the platforms we use
darwin_arm64=$(echo "$MANIFEST" | jq -r '.platforms["darwin-arm64"].checksum')
linux_x64=$(echo "$MANIFEST" | jq -r '.platforms["linux-x64"].checksum')

cat > "$VERSION_FILE" << EOF
{
  "version": "$VERSION",
  "platforms": {
    "darwin-arm64": "$darwin_arm64",
    "linux-x64": "$linux_x64"
  }
}
EOF

echo "Updated $VERSION_FILE to v${VERSION}"
