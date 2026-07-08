{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.ddclient;
in {
  options.dedsm.ddclient = {
    enable = mkOption {
      description = "Dynamic DNS updates (ddclient)";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    services.ddclient = {
      enable = true;
      configFile = "/etc/nixos/ddclient.conf";
    };
  };
}
