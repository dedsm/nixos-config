{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.zoxide.enable or false) {
  programs.zoxide = {
    enable = true;
    enableZshIntegration = false;
  };
}
