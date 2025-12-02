{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.gnome-programs;
in {
  options.dedsm.gnome-programs = {
    enable = mkOption {
      description = "Gnome Programs";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    programs.gnome-disks.enable = true;
    programs.seahorse.enable = true;
  };
}
