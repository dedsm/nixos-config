attrs@{ lib, homeManagerConfig, pkgs, ... }:
let
  waybar = import ./waybar attrs;
  hyprdynamicmonitors = import ./hyprdynamicmonitors attrs;
  hypridle = import ./hypridle attrs;
  hyprlock = import ./hyprlock attrs;
in with lib;
mkIf (homeManagerConfig.wayland.enable or false) (mkMerge [ waybar hyprdynamicmonitors hypridle hyprlock ])
