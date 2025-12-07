{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.mako.enable or false) {
  services.mako = {
    enable = true;
    package = pkgs.unstable.mako;
    settings = {
      default-timeout = 5000;
      "mode=do-not-disturb" = {
        invisible = "1";
      };
    };
  };
}
