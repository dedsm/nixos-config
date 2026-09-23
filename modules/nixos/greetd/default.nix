{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.dedsm.greetd;
  greeterCfg = config.services.displayManager.dms-greeter;
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

    # 26.05's dms-greeter module builds its greetd command against the pre-1.6
    # layout: `sh ${package}/share/quickshell/dms/Modules/Greetd/assets/dms-greeter`
    # plus `-p ${package}/share/quickshell/dms`. Neither path exists any more.
    # Upstream split the greeter into its own repo (AvengeMedia/dank-greeter),
    # nixpkgs packages it separately as `dms-greeter` with the UI baked into the
    # binary the same way dms-shell now bakes its own, and unstable's module was
    # rewritten to exec `${package}/bin/dms-greeter` with no `-p` at all. 26.05
    # has not caught up, and its `package` option defaults to
    # `programs.dms-shell.package` — so our 1.6.2 shell flows straight into a
    # path that is gone, and greetd is left with a command it cannot exec.
    #
    # Nothing else in the 26.05 module is stale: its config block differs from
    # unstable's only in miracle-wm attribute pathing and `config.systemd.package`
    # vs `pkgs.systemd` in the autologin branch, neither of which applies here.
    # So the whole repair is this one command, and everything else — the
    # `dms-greeter` user, the cache dir, greetd's settings, the PAM stack — keeps
    # coming from the module. Delete this block when 26.05 backports the rewrite.
    #
    # Reproduced from unstable's `greeterScript`, reading the module's own option
    # values rather than re-deriving them, so only the exec line is duplicated.
    # `pkgs.glib` is not carried over from 26.05 — it is new in unstable's
    # version, for the gdbus the greeter's fprintd probe and portal reads need.
    services.greetd.settings.default_session.command = mkForce (
      getExe (
        pkgs.writeShellScriptBin "dms-greeter-start" ''
          export PATH=$PATH:${
            makeBinPath [
              greeterCfg.quickshell.package
              config.programs.hyprland.package
              pkgs.glib
            ]
          }
          ${
            escapeShellArgs (
              [
                "${pkgs.unstable.dms-greeter}/bin/dms-greeter"
                "--cache-dir"
                "/var/lib/dms-greeter"
                "--command"
                greeterCfg.compositor.name
              ]
              ++ optionals (greeterCfg.compositor.customConfig != "") [
                "-C"
                "${pkgs.writeText "dmsgreeter-compositor-config" greeterCfg.compositor.customConfig}"
              ]
            )
          } ${optionalString greeterCfg.logs.save "> ${greeterCfg.logs.path} 2>&1"}
        ''
      )
    );

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
