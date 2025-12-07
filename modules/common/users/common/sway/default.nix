attrs@{ lib, homeManagerConfig, pkgs, ... }:
let
  wm = import ./wm attrs;
in with lib; mkIf (homeManagerConfig.sway.enable or false) (mkMerge [ wm ])
