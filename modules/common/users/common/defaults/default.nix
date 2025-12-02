attrs@{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
let
  common = import ./common attrs;
in with lib;
mkIf homeManagerConfig.defaults.enable (mkMerge [ common ])
