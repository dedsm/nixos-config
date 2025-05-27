{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.mako.enable {
  services.mako = {
    enable = true;
    package = unstablePkgs.mako;
    settings = {
      default-timeout = 5000;
      "mode=do-not-disturb" = {
        invisible = "1";
      };
    };
  };
}
