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

    autologinUser = mkOption {
      description = ''
        User to boot straight into the Hyprland session, skipping the greeter.
        hyprlock (launched first thing by Hyprland's autostart) is the actual
        authentication gate; LUKS remains the at-rest security boundary.
        tuigreet stays as the fallback greeter after logout. See
        docs/login-flow.md.
      '';
      type = with types; nullOr str;
      default = null;
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
      }
      // optionalAttrs (cfg.autologinUser != null) {
        initial_session = {
          command = "uwsm start hyprland-uwsm.desktop";
          user = cfg.autologinUser;
        };
      };
    };

    # The stock unit is Type=idle: systemd delays exec until the boot job queue
    # drains, so any slow boot oneshot (powertop, fwupd refresh, ...) holds the
    # login prompt hostage for up to the 5s idle cap. Worst case with exec is a
    # late boot message printing over tuigreet.
    systemd.services.greetd.serviceConfig.Type = mkForce "exec";

    # With autologin no password flows through PAM at login, so gnome-keyring
    # is unlocked at the hyprlock gate instead: pam_gnome_keyring's auth
    # handler forwards the typed password to the already-running daemon.
    # Requires the login keyring's password to equal the user password, and a
    # password (not fingerprint) unlock — enforced after boot/resume by the
    # strict hyprlock config (see docs/login-flow.md).
    security.pam.services.hyprlock.enableGnomeKeyring = true;

    security.pam.services.greetd.fprintAuth = false;
  };
}
