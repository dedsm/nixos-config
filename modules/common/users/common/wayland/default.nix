attrs@{ lib, homeManagerConfig, pkgs, ... }:
let
  waybar = import ./waybar attrs;
  kanshi = import ./kanshi attrs;
  hypridle = import ./hypridle attrs;
  hyprlock = import ./hyprlock attrs;
  flameshot = import ./flameshot attrs;
in with lib;
mkIf (homeManagerConfig.wayland.enable or false) (mkMerge [ waybar kanshi hypridle hyprlock flameshot ])
