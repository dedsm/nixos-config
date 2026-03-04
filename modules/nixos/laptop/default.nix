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
      HandleLidSwitch = "hibernate";
      HandleLidSwitchDocked = "ignore";
      HandleLidSwitchExternalPower = "hibernate";
    };

    systemd.tmpfiles.rules = [ "w /sys/power/image_size - - - - 0" ];

    # Power management
    services.upower = { enable = true; };
    services.power-profiles-daemon.enable = true;

    hardware.amdgpu = {
      initrd.enable = true;
      opencl.enable = true;
    };
  };
}
