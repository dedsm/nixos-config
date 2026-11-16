{
  lib,
  vimUtils,
  fetchFromGitHub,
  nix-update,
}:
# herdr-desktop (Herdr.app) mod plus Neovim plugin: ctrl+<direction> moves
# between Neovim windows first and on through Herdr.app panes at Neovim's edge.
# The repo is both at once — `mods/edge-nav/` is the app mod, `lua/` and
# `plugin/` the Neovim plugin — so it is built as a Vim plugin and the
# herdr-desktop module takes the mod from `$out/mods/edge-nav`, setting its
# options there. Upstream as-is here. See docs/herdr.md, "herdr-desktop (trial)".
vimUtils.buildVimPlugin {
  pname = "herdr-app-edge-nav";
  version = "0-unstable-2026-11-09";

  src = fetchFromGitHub {
    owner = "sebcbi1";
    repo = "herdr-app-edge-nav";
    rev = "94b698f87c938c05bdbb33778f1deb8249280c88";
    hash = "sha256-9LYvGWOxq+0MT4zmHu5FS+vlTYOXPkj435dcDy4OSN8=";
  };

  # Upstream tags nothing, so the pin follows the default branch and the version
  # carries the commit date. `scripts/update-packages.sh` runs this.
  passthru.updateScript = [
    (lib.getExe nix-update)
    "--flake"
    "--version=branch"
    "herdr-app-edge-nav"
  ];

  meta = {
    description = "Herdr.app mod and Neovim plugin for directional pane navigation across Neovim splits";
    homepage = "https://github.com/sebcbi1/herdr-app-edge-nav";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
