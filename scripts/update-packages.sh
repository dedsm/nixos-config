#!/usr/bin/env bash
#
# Bump the pinned sources this repo maintains by hand.
#
# Two kinds of updater are collected here:
#
#   * packages under pkgs/ that carry `passthru.updateScript` — the nixpkgs
#     convention, usually a `nix-update --flake <attr>` invocation. These are
#     discovered from the flake's `packages` output, so adding one to a package
#     is enough; there is no list here to keep in sync.
#
#   * scripts under scripts/updaters/, named update-<name>.sh, for things that
#     are not packages in pkgs/ (claude-code pins a manifest.zst.json inside a
#     home-manager module, so there is no derivation to hang an updateScript
#     off). Dropping an executable script in that directory registers it.
#
# Nothing here is run automatically. Updates are reviewed with `git diff` and
# then applied with a normal rebuild.
#
# Usage:
#   scripts/update-packages.sh              # update everything
#   scripts/update-packages.sh <name> ...   # update only these
#   scripts/update-packages.sh --list       # show what can be updated
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

# Updaters that are not a package's updateScript: scripts/updaters/update-<name>.sh
UPDATER_DIR="$REPO_DIR/scripts/updaters"
declare -A EXTRA_UPDATERS=()
for script in "$UPDATER_DIR"/update-*.sh; do
  [ -x "$script" ] || continue
  name="$(basename "$script" .sh)"
  EXTRA_UPDATERS[${name#update-}]="$script"
done

# Anything that deliberately has no updater, with the reason. Empty is fine —
# this exists so an un-automatable pin is recorded rather than silently missing.
declare -A MANUAL_ONLY=()

system="$(nix eval --raw --impure --expr builtins.currentSystem)"

# Package attrs on this system that expose an updateScript.
mapfile -t auto_updatable < <(
  nix eval --json ".#packages.${system}" \
    --apply 'ps: builtins.filter (n: ps.${n} ? updateScript) (builtins.attrNames ps)' |
    jq -r '.[]'
)

list() {
  echo "Auto-updatable packages (passthru.updateScript, system ${system}):"
  if [ ${#auto_updatable[@]} -eq 0 ]; then
    echo "  (none)"
  else
    for name in "${auto_updatable[@]}"; do
      version="$(nix eval --raw ".#packages.${system}.${name}.version" 2>/dev/null || echo "?")"
      printf '  %-24s %s\n' "$name" "$version"
    done
  fi

  echo
  echo "Other updaters (scripts/updaters):"
  if [ ${#EXTRA_UPDATERS[@]} -eq 0 ]; then
    echo "  (none)"
  else
    for name in "${!EXTRA_UPDATERS[@]}"; do
      printf '  %-24s %s\n' "$name" "${EXTRA_UPDATERS[$name]#"$REPO_DIR"/}"
    done
  fi

  echo
  echo "Manual only:"
  if [ ${#MANUAL_ONLY[@]} -eq 0 ]; then
    echo "  (none)"
  else
    for name in "${!MANUAL_ONLY[@]}"; do
      printf '  %-24s %s\n' "$name" "${MANUAL_ONLY[$name]}"
    done
  fi
}

update_one() {
  local name="$1"

  if [[ -n "${EXTRA_UPDATERS[$name]:-}" ]]; then
    echo "==> $name"
    "${EXTRA_UPDATERS[$name]}"
    return
  fi

  if [[ -n "${MANUAL_ONLY[$name]:-}" ]]; then
    echo "==> $name: manual only — ${MANUAL_ONLY[$name]}" >&2
    return
  fi

  local found=0
  for candidate in "${auto_updatable[@]}"; do
    [[ "$candidate" == "$name" ]] && found=1 && break
  done
  if [[ $found -eq 0 ]]; then
    echo "==> $name: no updater (not a package with passthru.updateScript on ${system})" >&2
    return 1
  fi

  echo "==> $name"
  # Read the command by building it into a JSON file rather than `nix eval`ing
  # it: eval strips the string context recording which store paths the command
  # references, so the tool it points at may not exist locally (e.g. right
  # after a flake.lock bump). Building a writeText realizes every referenced
  # path as an ordinary dependency — the same mechanism nixpkgs'
  # maintainers/scripts/update.nix uses. Accepts the conventional updateScript
  # forms: a list, a bare executable, or { command, ... }.
  local json cmd
  json="$(nix build --no-link --print-out-paths --impure --expr "
    let
      flake = builtins.getFlake \"$REPO_DIR\";
      us = flake.packages.\"$system\".\"$name\".updateScript;
      pkgs = flake.inputs.nixpkgs.legacyPackages.\"$system\";
    in
    pkgs.writeText \"update-command.json\"
      (builtins.toJSON (map toString (pkgs.lib.toList (us.command or us))))
  ")"
  mapfile -t cmd < <(jq -r '.[]' "$json")
  "${cmd[@]}"
}

case "${1:-}" in
  --list | -l)
    list
    exit 0
    ;;
  --help | -h)
    sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    exit 0
    ;;
esac

if [ $# -gt 0 ]; then
  targets=("$@")
else
  targets=("${auto_updatable[@]}" "${!EXTRA_UPDATERS[@]}")
fi

failed=()
for name in "${targets[@]}"; do
  update_one "$name" || failed+=("$name")
done

echo
if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed: ${failed[*]}" >&2
  exit 1
fi
echo "Done. Review with 'git diff', then rebuild."
