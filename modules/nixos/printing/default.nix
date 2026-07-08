{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.printing;
in {
  options.dedsm.printing = {
    enable = mkOption {
      description = "CUPS printing";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    services.printing = {
      enable = true;
      browsing = true;
      startWhenNeeded = true;
      drivers = [ pkgs.unfree.epson_201207w pkgs.gutenprint ];
    };
  };
}
