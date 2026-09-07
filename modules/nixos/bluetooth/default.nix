{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.dedsm.bluetooth;
in
{
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

    # No blueman: DMS's control centre is the pairing/connection UI, and
    # `services.blueman.enable` ships an XDG autostart entry that the systemd
    # generator turns into a user unit — a second tray icon beside DMS's own,
    # which survives having no home-manager unit because nothing here starts it.
  };
}
