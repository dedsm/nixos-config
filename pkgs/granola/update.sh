# Bump pkgs/granola to the release Granola's own auto-updater is serving, then
# re-pin the better-sqlite3-multiple-ciphers release binding.gyp comes from to
# whatever that release bundles. Run from the repo root (scripts/update-packages.sh
# does). Body of a writeShellApplication, so errexit/nounset/pipefail are on.

file=pkgs/granola/default.nix
bundle=Granola.app/Contents

feed="$(curl -fsSL https://api.granola.ai/v1/check-for-update/latest-mac.yml)"
version="$(yq -r .version <<<"$feed")"
hash="sha512-$(yq -r .sha512 <<<"$feed")"

if [[ "$(yq -r .path <<<"$feed")" != "Granola-$version-mac-universal.zip" ]]; then
  echo "granola: the feed's payload is now $(yq -r .path <<<"$feed"); update src.url in $file" >&2
  exit 1
fi

oldVersion="$(nix eval --raw .#granola.version)"
if [[ "$version" == "$oldVersion" ]]; then
  echo "granola: already at $version"
  exit 0
fi

oldHash="$(nix eval --raw .#granola.src.outputHash)"
sed -i -e "s|version = \"$oldVersion\";|version = \"$version\";|" -e "s|$oldHash|$hash|" "$file"
echo "granola: $oldVersion -> $version"

# Fetching src here also leaves it in the store for the rebuild.
zip="$(nix build --no-link --print-out-paths .#granola.src)"

sqliteVersion="$(unzip -p "$zip" \
  "$bundle/Resources/app.asar.unpacked/node_modules/better-sqlite3-multiple-ciphers/package.json" |
  jq -r .version)"
oldSqliteVersion="$(nix eval --raw .#granola.sqliteCipher.version)"
if [[ "$sqliteVersion" != "$oldSqliteVersion" ]]; then
  oldSqliteHash="$(nix eval --raw .#granola.sqliteCipher.src.outputHash)"
  sqliteHash="$(curl -fsSL "https://registry.npmjs.org/better-sqlite3-multiple-ciphers/$sqliteVersion" |
    jq -r .dist.integrity)"
  sed -i -e "s|version = \"$oldSqliteVersion\";|version = \"$sqliteVersion\";|" \
    -e "s|$oldSqliteHash|$sqliteHash|" "$file"
  echo "granola: better-sqlite3-multiple-ciphers $oldSqliteVersion -> $sqliteVersion"
fi

electronVersion="$(unzip -p "$zip" \
  "$bundle/Frameworks/Electron Framework.framework/Versions/A/Resources/Info.plist" |
  grep -A1 CFBundleVersion | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
electronMajor="${electronVersion%%.*}"
pinnedElectron="$(nix eval --raw .#granola.electron.version)"
if [[ "$electronMajor" != "${pinnedElectron%%.*}" ]]; then
  echo "granola: $version ships Electron $electronVersion; switch the granola entry in pkgs/default.nix to electron_$electronMajor" >&2
  exit 1
fi
