{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.direnv.enable or false) {
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    stdlib = builtins.readFile ./direnvrc;
    config = {global = {warn_timeout = "3000h";};};
  };
}
