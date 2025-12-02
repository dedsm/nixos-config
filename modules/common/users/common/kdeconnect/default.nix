{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.kdeconnect.enable {
  services.kdeconnect = {
    enable = true;
    indicator = true;
  };
}
