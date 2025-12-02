{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.network-manager.enable {
  services.network-manager-applet.enable = true;
}
