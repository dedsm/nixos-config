# Since I only have one system this is a placeholder for all the configurations I'd use in a laptop
# It should be split into more detailed modules if the situation ever changes (like having a dedicated desktop for instance)
{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.laptop;
in {
  options.dedsm.laptop = {
    enable = mkOption {
      description = "Laptop settings";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    # Hibernation rules
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchDocked = "ignore";
      HandleLidSwitchExternalPower = "suspend-then-hibernate";
    };

    systemd.sleep.settings.Sleep = {
      HibernateMode = "shutdown";
      HibernateDelaySec = "24h";
      HibernateOnACPower = "no";
    };

    systemd.tmpfiles.rules = [ "w /sys/power/image_size - - - - 0" ];

    # Power management
    services.upower = { enable = true; };
    services.power-profiles-daemon.enable = true;
    powerManagement.powertop.enable = true;
    # powertop --auto-tune takes ~6s; as a boot job it delays the login prompt
    # (see the greetd module's Type override). Run it off a timer instead of
    # inside the boot transaction.
    systemd.services.powertop.wantedBy = mkForce [ ];
    systemd.timers.powertop = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnBootSec = "30s";
    };
    powerManagement.powerDownCommands = ''
      # Disable all ACPI wakeup sources except the power button (PWRB) before suspend
      for dev in $(${pkgs.gawk}/bin/awk '$3 == "*enabled" && $1 != "PWRB" {print $1}' /proc/acpi/wakeup); do
        echo "$dev" > /proc/acpi/wakeup
      done
    '';

    hardware.amdgpu = {
      initrd.enable = true;
      opencl.enable = true;
    };

    # `light` was removed from nixpkgs in 26.05; brightnessctl is avizo's
    # lightctl backend and ships udev rules for the video group (no setuid).
    environment.systemPackages = [pkgs.brightnessctl];
    services.udev.packages = [pkgs.brightnessctl];
  };
}
