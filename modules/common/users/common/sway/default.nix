attrs@{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
let
  wm = import ./wm attrs;
in with lib; mkIf homeManagerConfig.sway.enable (mkMerge [ wm ])
