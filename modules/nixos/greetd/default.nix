{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.dedsm.greetd;
in
{
  options.dedsm.greetd = {
    enable = mkOption {
      description = ''
        greetd running DankMaterialShell's greeter, which authenticates before
        the Hyprland session exists. The alternative — autologin with the lock
        screen as the gate — reached a prompt marginally sooner but handed the
        console to the session first, so the eye saw VT text between the two.
        See docs/login-flow.md.
      '';
      type = with types; bool;
      default = false;
    };

    greeterUser = mkOption {
      description = ''
        Whose DMS configuration the greeter reads, so the login screen carries
        the same theme and wallpaper as the desktop behind it.
      '';
      type = with types; str;
      default = "david";
    };
  };

  config = mkIf cfg.enable {
    # The greeter brings its own `default_session`; nothing else declares one.
    services.greetd.enable = true;

    services.displayManager.dms-greeter = {
      enable = true;
      # Hyprland hosts the greeter, in a short-lived instance owned by the
      # `dms-greeter` user. Something lighter would start marginally sooner, but
      # 26.05's module only offers niri, hyprland and sway — no minimal
      # single-surface compositor like cage — and pulling in a whole second
      # compositor to draw one login screen is not worth the packages or the
      # untested code on the login path. Hyprland is already here.
      compositor.name = "hyprland";
      configHome = "/home/${cfg.greeterUser}";

      # Without this the greeter writes its own Hyprland config carrying only
      # `disable_hyprland_logo`, so the login screen is preceded by Hyprland's
      # default background and its splash line — the same two artefacts the
      # session's config turns off. Matched here, so the whole boot stays black
      # until something deliberate is drawn on it.
      #
      # Supplying a config *replaces* the generated one rather than extending
      # it, so two details have to be reproduced: `DMS_RUN_GREETER`, which is
      # how the shell knows it is running as the greeter, and lua syntax — the
      # launcher tells lua from hyprlang by looking for `hl.`
      # (`hyprlandLuaPattern` in dank-greeter's compositor.go) and only appends
      # its own start hook to a config it recognises as lua.
      compositor.customConfig = ''
        hl.env("DMS_RUN_GREETER", "1")

        hl.config({
          misc = {
            disable_hyprland_logo = true,
            disable_splash_rendering = true,
            force_default_wallpaper = 0,
            background_color = "rgb(000000)",
          },
        })
      '';
    };

    # A password flows through PAM at login here, which is the ordinary way to
    # unlock the login keyring — so the lock screen does not have to.
    security.pam.services.greetd.enableGnomeKeyring = true;

    # The stock unit is Type=idle: systemd delays exec until the boot job queue
    # drains, so any slow boot oneshot (powertop, fwupd refresh, ...) holds the
    # login prompt hostage for up to the 5s idle cap. Worst case with exec is a
    # late boot message printing over the greeter.
    systemd.services.greetd.serviceConfig.Type = mkForce "exec";

    # Fingerprint is not offered at login: dedsm.fingerprintPolicy denies it
    # after a boot anyway — its state lives in /run, so nothing has
    # authenticated yet — and a prompt that can only fail is worse than none.
    security.pam.services.greetd.fprintAuth = false;
  };
}
