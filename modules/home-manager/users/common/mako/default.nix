{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.mako.enable {
  services.mako = {
    enable = true;
    defaultTimeout = 5000;
    package = unstablePkgs.mako;
    extraConfig = ''
      [mode=do-not-disturb]
      invisible=1
    '';
  };
}
