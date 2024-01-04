attrs@{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
let
  common = import ./common attrs;
  waybar = import ./waybar attrs;
  kanshi = import ./kanshi attrs;
in with lib;
mkIf homeManagerConfig.wayland.enable (mkMerge [ common waybar kanshi ])
