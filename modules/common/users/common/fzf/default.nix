{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.fzf.enable or false) {
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
}
