{
  unstablePkgs,
}:
self: super: {
  cli-notify = super.callPackage ./cli-notify { };

  dstask-note = super.callPackage ./dstask-note { };

  # Herdr's Neovim-aware pane navigation: the herdr-desktop mod and its Neovim
  # half, from one repo. Installed by the herdr module.
  herdr-app-edge-nav = super.callPackage ./herdr-app-edge-nav { };

  # Granola's macOS build on nixpkgs' Electron, built with unstable's
  # callPackage. Granola is proprietary, so it is on unstable's unfree allowlist
  # in lib/pkgs.nix. The Electron major must match the one Granola ships, which
  # the build checks; see docs/granola.md.
  granola = unstablePkgs.callPackage ./granola { electron = unstablePkgs.electron_45; }; # unfree (lib/pkgs.nix)
}
