attrs@{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
let
  waybar = import ./waybar attrs;
  kanshi = import ./kanshi attrs;
  swayidle = import ./swayidle attrs;
  flameshot = import ./flameshot attrs;
in with lib;
mkIf homeManagerConfig.wayland.enable (mkMerge [ waybar kanshi swayidle flameshot ])
