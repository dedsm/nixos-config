{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.lorri.enable or false) {
  services.lorri.enable = true;
}
