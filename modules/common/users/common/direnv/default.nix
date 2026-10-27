{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
with lib;
mkIf (homeManagerConfig.direnv.enable or false) {
  programs.direnv = {
    enable = true;
    package = pkgs.unstable.direnv;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config = {
      global = {
        warn_timeout = "3000h";
      };
    };
  };
}
