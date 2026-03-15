{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.bluetooth.enable or false) {
  services.blueman-applet = {
    enable = true;
    systemdTargets = [ "tray.target" ];
  };
}
