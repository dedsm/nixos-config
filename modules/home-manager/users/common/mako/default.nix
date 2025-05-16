{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.mako.enable {
  services.mako = {
    enable = true;
    package = unstablePkgs.mako;
    criteria = {
      "mode=do-not-disturb" = {
        invisible = "1";
      };
    };
    settings = {
      default-timeout = 5000;
    };
  };
}
