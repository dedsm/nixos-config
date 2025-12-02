{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.lorri.enable {
  services.lorri.enable = true;
}
