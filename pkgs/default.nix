{ hyprlandPkgs, unstablePkgs }:
self: super:
let
  pkgsPath = ./.;
in
{
  slack = super.callPackage ./slack { slack = unstablePkgs.slack; };

  cli-notify = super.callPackage ./cli-notify { };

  dstask-note = super.callPackage ./dstask-note { };

  # herdr itself comes from unstable, and the plugin's wrapper has to call the
  # same binary the user runs.
  vim-herdr-navigation = super.callPackage ./vim-herdr-navigation {
    herdr = unstablePkgs.herdr;
  };
}
