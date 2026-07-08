{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.bluetooth;
in {
  options.dedsm.bluetooth = {
    enable = mkOption {
      description = "Bluetooth hardware + Blueman";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      package = pkgs.unstable.bluez;
    };

    services.blueman.enable = true;
  };
}
