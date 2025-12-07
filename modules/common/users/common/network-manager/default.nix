{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.network-manager.enable or false) {
  services.network-manager-applet.enable = true;
}
