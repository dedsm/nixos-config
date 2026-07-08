{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.greetd;
in {
  options.dedsm.greetd = {
    enable = mkOption {
      description = "greetd login manager, defaulting into the Hyprland session";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-user-session --asterisks --user-menu --cmd 'uwsm start hyprland-uwsm.desktop'";
          user = "greeter";
        };
      };
    };

    security.pam.services.greetd.fprintAuth = false;
  };
}
