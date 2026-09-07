attrs@{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
let
  hyprdynamicmonitors = import ./hyprdynamicmonitors attrs;
in
with lib;
mkIf (homeManagerConfig.wayland.enable or false) (mkMerge [
  hyprdynamicmonitors
])
