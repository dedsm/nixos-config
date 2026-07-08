{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.hyprland;
in {
  options.dedsm.hyprland = {
    enable = mkOption {
      description = "System-level Hyprland session support";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    system.nixos.tags = [ "hyprland" ];

    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };

    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
  };
}
