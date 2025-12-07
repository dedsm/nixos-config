{ lib, pkgs, homeManagerConfig, ... }:
with lib;
mkIf (homeManagerConfig.sketchybar.enable or false) {
  programs.sketchybar = {
    enable = true;
    config = builtins.readFile ./sketchybarrc;
  };

  xdg.configFile."sketchybar/colors.sh".source = ./colors.sh;
  xdg.configFile."sketchybar/plugins".source = ./plugins;
}
