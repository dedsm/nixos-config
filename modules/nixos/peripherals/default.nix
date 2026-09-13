{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.dedsm.peripherals;
in
{
  options.dedsm.peripherals = {
    enable = mkOption {
      description = "David's laptop peripherals: drawing tablet, Ledger, Logitech receiver, fingerprint reader, Thunderbolt, YubiKey, game controllers";
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

    # Fingerprint reader. The lock screen runs fingerprint in its own PAM
    # context (see security.pam.services.dankshell in the greetd module), so
    # the password stack stays password-only; tty login stays password-only
    # too. `sudo` keeps NixOS' default (fprintAuth follows
    # services.fprintd.enable) and so does accept a fingerprint. What *any* of
    # them may do is bounded by dedsm.fingerprintPolicy — see
    # docs/login-flow.md.
    services.fprintd.enable = true;
    security.pam.services.login.fprintAuth = false;

    # Thunderbolt
    services.hardware.bolt.enable = true;

    # YubiKey
    services.pcscd.enable = true;

    services.udev.packages = [ pkgs.yubikey-personalization ];

    # Game controllers. The kernel binds a DualSense on its own
    # (hid-playstation) and logind ACLs its evdev/joystick nodes, so games see
    # the pad with none of this. The *hidraw* node is the one that needs a
    # rule — rumble, the LEDs, the gyro, the battery level, everything Steam
    # Input drives — tagging it `uaccess`, which hands it to whoever is logged
    # in at the seat rather than to a group that outlives the session.
    #
    # This is steam-hardware rather than the broader
    # `pkgs.game-devices-udev-rules`, and the reason is the *filename*. udev
    # reads rules in lexical order and systemd's 73-seat-late.rules is what
    # turns a `uaccess` tag into an ACL, so a rule that tags the device must
    # sort before it. nixpkgs installs the game-devices rules unprefixed
    # (`sony-gdu.rules`), which sorts after 73: the first plug gets MODE=0660
    # and no ACL. It then looks fixed on any re-trigger, because that rule
    # matches with `TAG==`, which also sees the tag the previous run left in
    # the udev database — so the bug hides itself the moment you poke it.
    # Steam's rules ship as 60-steam-input.rules and carry the same DualSense
    # ids (054c:0ce6, USB and Bluetooth).
    hardware.steam-hardware.enable = true;
    services.udev.extraRules = ''
      # Disable wakeup on Logitech USB receiver to prevent spurious resume from suspend
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="046d", ATTR{idProduct}=="c548", ATTR{power/wakeup}="disabled"
    '';
  };
}
