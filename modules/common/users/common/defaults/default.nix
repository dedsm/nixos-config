attrs@{ lib, homeManagerConfig, pkgs, ... }:
let
  common = import ./common attrs;
in with lib;
mkIf (homeManagerConfig.defaults.enable or false) (mkMerge [ common ])
