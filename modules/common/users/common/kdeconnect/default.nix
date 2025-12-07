{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.kdeconnect.enable or false) {
  services.kdeconnect = {
    enable = true;
    indicator = true;
  };
}
