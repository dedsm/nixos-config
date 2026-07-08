{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.scanning;
in {
  options.dedsm.scanning = {
    enable = mkOption {
      description = "Document/photo scanning (SANE)";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    hardware.sane = {
      enable = true;
      extraBackends = [ pkgs.sane-airscan ];
    };
  };
}
