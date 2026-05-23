#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_DIR/modules/common/users/common/antigravity/version.json"

UA="Mozilla/5.0"

IDE_BASE="https://antigravity-ide-auto-updater-974169037036.us-central1.run.app/api/update"
CLI_BASE="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests"

echo "Fetching latest Antigravity IDE manifests..."
ide_x64=$(curl -fsSL -A "$UA" "$IDE_BASE/linux-x64/stable/latest")
ide_arm=$(curl -fsSL -A "$UA" "$IDE_BASE/linux-arm64/stable/latest")

# Manifest 'version' field is a git hash; the human version lives inside the URL.
ide_version=$(echo "$ide_x64" | jq -r '.url' | sed -nE 's|.*/stable/([0-9.]+)-[0-9]+/.*|\1|p')
ide_vscode=$(echo "$ide_x64" | jq -r '.productVersion')
ide_x64_url=$(echo "$ide_x64" | jq -r '.url' | sed 's/ /%20/g')
ide_x64_sha=$(echo "$ide_x64" | jq -r '.sha256hash')
ide_arm_url=$(echo "$ide_arm" | jq -r '.url' | sed 's/ /%20/g')
ide_arm_sha=$(echo "$ide_arm" | jq -r '.sha256hash')

echo "Fetching latest Antigravity CLI manifests..."
cli_x64=$(curl -fsSL -A "$UA" "$CLI_BASE/linux_amd64.json")
cli_arm=$(curl -fsSL -A "$UA" "$CLI_BASE/linux_arm64.json")

cli_version=$(echo "$cli_x64" | jq -r '.version')
cli_x64_url=$(echo "$cli_x64" | jq -r '.url')
cli_x64_sha=$(echo "$cli_x64" | jq -r '.sha512')
cli_arm_url=$(echo "$cli_arm" | jq -r '.url')
cli_arm_sha=$(echo "$cli_arm" | jq -r '.sha512')

cat > "$VERSION_FILE" <<EOF
{
  "ide": {
    "version": "$ide_version",
    "vscodeVersion": "$ide_vscode",
    "sources": {
      "x86_64-linux": {
        "url": "$ide_x64_url",
        "sha256": "$ide_x64_sha"
      },
      "aarch64-linux": {
        "url": "$ide_arm_url",
        "sha256": "$ide_arm_sha"
      }
    }
  },
  "cli": {
    "version": "$cli_version",
    "sources": {
      "x86_64-linux": {
        "url": "$cli_x64_url",
        "sha512": "$cli_x64_sha"
      },
      "aarch64-linux": {
        "url": "$cli_arm_url",
        "sha512": "$cli_arm_sha"
      }
    }
  }
}
EOF

echo "Updated $VERSION_FILE: IDE $ide_version (vscode $ide_vscode), CLI $cli_version"
