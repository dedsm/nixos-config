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
    services.logind = {
      lidSwitch = "suspend-then-hibernate";
      lidSwitchDocked = "ignore";
      lidSwitchExternalPower = "suspend";
    };
    systemd.sleep.extraConfig = "HibernateDelaySec=1800";

    systemd.tmpfiles.rules = [ "w /sys/power/image_size - - - - 0" ];

    # Power management
    services.upower = { enable = true; };

    services.tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "powersave";
        INTEL_GPU_MIN_FREQ_ON_AC = 500;
        INTEL_GPU_MAX_FREQ_ON_AC = 1450;
        INTEL_GPU_BOOST_FREQ_ON_AC = 1450;
      };
    };
  };
}
