{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.gnome-services;
in {
  options.dedsm.gnome-services = {
    enable = mkOption {
      description = "Gnome Services";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {

    systemd.packages = with pkgs; [ gnome-session ];
    services.gvfs.enable = true;

    services.gnome = {
      gnome-keyring = { enable = true; };
      sushi = { enable = true; };
      gnome-settings-daemon = { enable = true; };
      at-spi2-core = { enable = true; };
    };

    services.udisks2 = { enable = true; };

    services.udev = {
      packages = with pkgs; [
        gnome-settings-daemon
      ];
    };
  };
}
