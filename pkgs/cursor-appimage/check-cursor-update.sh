#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq coreutils nix-prefetch-scripts nix

set -eu -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIX_FILE="$PACKAGE_DIR/default.nix"

echo -e "${BLUE}Checking for Cursor updates...${NC}"
echo -e "${BLUE}Using Nix file: $NIX_FILE${NC}"

# Get current version from the nix file
currentVersion=$(grep 'version = ' "$NIX_FILE" | head -1 | sed 's/.*version = "\(.*\)".*/\1/')
if [ -z "$currentVersion" ]; then
    echo -e "${RED}Could not extract current version from $NIX_FILE${NC}"
    exit 1
fi
echo -e "${YELLOW}Current version in $NIX_FILE: $currentVersion${NC}"

# Get latest version info from Cursor API
echo -e "${BLUE}Fetching latest version information from Cursor API...${NC}"
api_result=$(curl -s "https://api2.cursor.sh/updates/api/download/stable/linux-x64/cursor")
latestVersion=$(echo "$api_result" | jq -r '.version')
latestUrl=$(echo "$api_result" | jq -r '.downloadUrl')

if [ -z "$latestVersion" ] || [ "$latestVersion" == "null" ]; then
    echo -e "${RED}Could not fetch latest version from API.${NC}"
    echo "API Response: $api_result"
    exit 1
fi

echo -e "${GREEN}Latest stable version available: $latestVersion${NC}"
echo -e "${GREEN}Latest download URL: $latestUrl${NC}"

if [[ "$latestVersion" == "$currentVersion" ]]; then
    echo -e "${GREEN}Your Cursor package is already up to date!${NC}"
    exit 0
fi

echo -e "${YELLOW}A new version is available: $latestVersion (you have $currentVersion)${NC}"
echo -e "${BLUE}To update, you will need to change version, URL, and sha256 in $NIX_FILE.${NC}"

echo -e "${BLUE}Prefetching new AppImage to calculate hash...${NC}"
# Prefetch the URL to get the store path and then calculate the SRI hash
# We use --name to ensure the output path is predictable if the file already exists in nix store,
# though nix-prefetch-url usually handles this.
prefetched_path=$(nix-prefetch-url "$latestUrl" --name "cursor-${latestVersion}.AppImage")

if [ -z "$prefetched_path" ]; then
    echo -e "${RED}Failed to prefetch the new AppImage from $latestUrl${NC}"
    exit 1
fi

echo -e "${BLUE}Calculating SRI hash for the new version...${NC}"
newSha256=$(nix-hash --to-sri --type sha256 "$prefetched_path")

if [ -z "$newSha256" ]; then
    echo -e "${RED}Failed to calculate SRI hash for $prefetched_path${NC}"
    exit 1
fi

echo -e "
${GREEN}Updating $NIX_FILE with the new version details...${NC}"

# Update version
sed -i "s/version = ".*"/version = "${latestVersion}"/" "$NIX_FILE"
echo -e "${GREEN}Updated version to: $latestVersion${NC}"

# Update URL
# Using a different sed delimiter because the URL contains slashes
sed -i "s|url = ".*"|url = "${latestUrl}"|" "$NIX_FILE"
echo -e "${GREEN}Updated URL to: $latestUrl${NC}"

# Update sha256
sed -i "s/sha256 = ".*"/sha256 = "${newSha256}"/" "$NIX_FILE"
echo -e "${GREEN}Updated sha256 to: $newSha256${NC}"

echo -e "
${GREEN}=== Automatic Update Complete ===${NC}"
echo -e "The file ${YELLOW}$NIX_FILE${NC} has been updated with:"
echo -e "  version = "${GREEN}$latestVersion${NC}";"
echo -e "  url     = "${GREEN}$latestUrl${NC}";"
echo -e "  sha256  = "${GREEN}$newSha256${NC}";"
echo ""
echo -e "${GREEN}You can now test the build with:${NC}"
echo -e "${YELLOW}nixos-rebuild build --flake .#manwe${NC} (or your hostname)"
echo -e "And apply with:"
echo -e "${YELLOW}nixos-rebuild switch --flake .#manwe${NC} (or your hostname)"
echo -e "
${GREEN}Update check and apply complete.${NC}"

# Make the script executable
# chmod +x "$PACKAGE_DIR/check-cursor-update.sh" 