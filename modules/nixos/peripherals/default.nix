{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.peripherals;
in {
  options.dedsm.peripherals = {
    enable = mkOption {
      description = "David's laptop peripherals: drawing tablet, Ledger, Logitech receiver, fingerprint reader, Thunderbolt, YubiKey";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    # Open Tablet Driver
    hardware.opentabletdriver = {
      enable = true;
      package = pkgs.unstable.opentabletdriver;
    };

    # Ledger support
    hardware.ledger.enable = true;

    # Logitech control
    hardware.logitech.wireless = {
      enable = true;
      enableGraphical = true;
    };
    # solaar needs users to be able to write to uinput
    hardware.uinput.enable = true;

    # Fingerprint reader is present but not used for unlock/login/lock screen
    services.fprintd.enable = true;
    security.pam.services.login.fprintAuth = false;
    security.pam.services.hyprlock.fprintAuth = false;

    # Thunderbolt
    services.hardware.bolt.enable = true;

    # YubiKey
    services.pcscd.enable = true;
    services.udev.packages = [ pkgs.yubikey-personalization ];
    services.udev.extraRules = ''
      # Disable wakeup on Logitech USB receiver to prevent spurious resume from suspend
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="046d", ATTR{idProduct}=="c548", ATTR{power/wakeup}="disabled"
    '';
  };
}
