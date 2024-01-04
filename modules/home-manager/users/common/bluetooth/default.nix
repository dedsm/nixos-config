{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.bluetooth.enable {
  services.blueman-applet.enable = true;
}
