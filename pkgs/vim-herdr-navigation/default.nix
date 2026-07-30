{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  bash,
  jq,
  herdr,
  nix-update,
}:
# herdr plugin: vim-tmux-navigator ported to herdr's CLI. The herdr half decides
# per keypress whether to forward `ctrl+h/j/k/l` into a Vim/Neovim pane or to
# move herdr's pane focus; the Neovim half (installed by the herdr module into
# `nvim/after/plugin/`) crosses back out at a split edge.
#
# Packaged rather than `herdr plugin install`ed: that command clones from GitHub
# and builds at runtime. Here the checkout is a fixed store path and the herdr
# module only has to register it. See docs/herdr.md.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "vim-herdr-navigation";
  version = "0.1.0-unstable-2026-06-28";

  src = fetchFromGitHub {
    owner = "paulbkim-dev";
    repo = "vim-herdr-navigation";
    rev = "53e318c772c4d3b7fbd904ac43bcf3e5b5d8b244";
    hash = "sha256-vUUt46jiK6ZsPH8D13/+IIlqT3KbFliPJkNplsVqiQo=";
  };

  nativeBuildInputs = [makeWrapper];
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    share=$out/share/${finalAttrs.pname}
    install -Dm755 navigate.sh $share/navigate.sh
    install -Dm644 editor/nvim.lua $share/editor/nvim.lua
    install -Dm644 editor/vim.vim $share/editor/vim.vim

    # `navigate.sh` shells out to `jq` (Vim detection; without it every key just
    # moves the pane focus) and to herdr itself, which it takes from
    # $HERDR_BIN_PATH. Neither is on PATH when herdr spawns a plugin action.
    makeWrapper ${bash}/bin/bash $out/bin/vim-herdr-navigate \
      --add-flags $share/navigate.sh \
      --prefix PATH : ${lib.makeBinPath [jq]} \
      --set-default HERDR_BIN_PATH ${lib.getExe herdr}

    # The manifest ships `command = ["bash", "navigate.sh", "<dir>"]`, which
    # assumes both a PATH and a working directory. Point it at the wrapper so it
    # assumes neither; herdr reads this copy, next to the scripts it describes.
    substitute herdr-plugin.toml $share/herdr-plugin.toml \
      --replace-fail '["bash", "navigate.sh", ' '["'$out'/bin/vim-herdr-navigate", '

    runHook postInstall
  '';

  # Upstream tags nothing, so the pin follows the default branch and the version
  # carries the commit date. `scripts/update-packages.sh` runs this.
  passthru.updateScript = [
    (lib.getExe nix-update)
    "--flake"
    "--version=branch"
    "vim-herdr-navigation"
  ];

  meta = {
    description = "Seamless ctrl+h/j/k/l navigation across herdr panes and Vim/Neovim splits";
    homepage = "https://github.com/paulbkim-dev/vim-herdr-navigation";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "vim-herdr-navigate";
  };
})
