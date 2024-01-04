attrs@{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
let
  swayidle = import ./swayidle attrs;
  wm = import ./wm attrs;
in with lib; mkIf homeManagerConfig.sway.enable (mkMerge [ swayidle wm ])
