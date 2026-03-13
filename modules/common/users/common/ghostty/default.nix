{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.ghostty.enable or false) {
  programs.ghostty = {
    enable = true;
    package = pkgs.unstable.ghostty-bin;
    settings = {
      font-family = "InconsolataGo Nerd Font Mono";
      font-size = 14;
      theme = "light:Selenized Light,dark:Selenized Dark";
    };
  };
}
