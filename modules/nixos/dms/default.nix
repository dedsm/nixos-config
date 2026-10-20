{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.dedsm.dms;
in
{
  options.dedsm.dms = {
    enable = mkOption {
      description = ''
        DankMaterialShell: the quickshell-based bar, notification centre,
        control centre, launcher and lock screen. Replaces waybar, swaync,
        hyprlock, hypridle, darkman and the tray applets — see docs/dms.md.
      '';
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    programs.dms-shell = {
      enable = true;
      # 26.05 ships 1.4.6; unstable is 1.6.3. Upstream's own flake runs ahead,
      # but mixing its package with this module drops some dependency wiring,
      # so track nixpkgs on both.
      #
      # One patch on top: it drops a `pkill -HUP -f 'gtk'` that ends every
      # icon-theme apply — see the comment at the patch and docs/dms.md. (Two
      # fingerprint patches used to sit here too; 1.6.3 fixed the same bug
      # upstream, see docs/dms.md.)
      #
      # This patches the *source* tree and re-runs `make sync-shell`, rather than
      # editing the installed tree. As of 1.6.x the QML shell is baked into the
      # Go binary — nixpkgs builds with the `withshell` tag, and `sync-shell`
      # copies `quickshell/` into `core/internal/shellembed/dist` for `go:embed`
      # — so `$out/share/quickshell` no longer exists and a postInstall
      # substitution has nothing to bite on. `sync-shell` is `rm -rf` plus a
      # fresh copy, so re-running it after the edit is safe and, importantly,
      # recomputes the `.dankrev` content hash the shell keys its extracted
      # copy on; patching the embed dir in place would leave that stale.
      package = pkgs.unstable.dms-shell.overrideAttrs (old: {
        preBuild = (old.preBuild or "") + ''
          # Applying an icon theme ends by SIGHUPing every process whose
          # command line contains "gtk", meant to make GTK apps re-read
          # settings.ini. GTK doesn't handle SIGHUP, so it kills them instead —
          # chiefly xdg-desktop-portal-gtk. With iconThemePerMode that happens
          # on every light/dark transition, right as the portal should be
          # announcing the new color-scheme, so Firefox missed each change
          # and stayed one mode behind. GTK apps get the icon theme live
          # through the portal anyway.
          substituteInPlace ../quickshell/Common/SettingsData.qml \
            --replace-fail "pkill -HUP -f 'gtk' 2>/dev/null || true" "true"

          # nixpkgs' preBuild has already run `make sync-shell` once, and the
          # copy it left behind carries the store's read-only permissions — so
          # the `rm -rf` that opens a second run fails without this.
          chmod -R u+w internal/shellembed/dist
          make sync-shell
        '';
      });
      systemd.enable = true;
      # khal isn't part of this setup; the widget stays empty without it.
      enableCalendarEvents = false;
    };

    # Start the shell in parallel with the compositor rather than after it.
    #
    # The packaged unit is After=graphical-session.target, and uwsm only reaches
    # that once Hyprland signals readiness — measured at 1.4s after Hyprland's
    # first frame on this machine. Every one of those milliseconds is unlocked
    # desktop on an autologin boot, because DMS *is* the locker: `lockAtStartup`
    # fires from Lock.qml's Component.onCompleted, and nothing can lock earlier
    # than the shell that owns the lock surface.
    #
    # All the shell actually needs is the Wayland socket, which exists as soon
    # as Hyprland has created it. So: order after uwsm's env export (which is
    # what puts WAYLAND_DISPLAY in the user manager), drop the target ordering,
    # and wait for the socket itself instead of for readiness.
    systemd.user.services.dms = {
      overrideStrategy = "asDropin";
      unitConfig = {
        # An empty value resets the list inherited from the packaged unit.
        After = [
          ""
          "wayland-wm-env@hyprland-uwsm.desktop.service"
        ];
        # The packaged unit is also Requisite=graphical-session.target, which
        # fails the start outright when the target is not up yet — so clearing
        # the ordering alone changes nothing. PartOf= is kept: the shell should
        # still stop with the session, it just should not wait for it.
        Requisite = [ "" ];
      };
      # DMS decides once, at startup, whether the sensor exists — by running
      # `fprintd-list $USER`. That call needs the polkit action
      # `net.reactivated.fprint.device.verify`, which dedsm.fingerprintPolicy
      # denies after a boot (its state lives in /run, so nothing has
      # authenticated yet). The probe therefore fails on every boot, DMS marks
      # fingerprint unavailable for the whole session, and the sensor is never
      # offered again — not even hours later when the policy would allow it.
      #
      # This flag skips the probe and lets the decision happen where it belongs:
      # at verify time, through fprintd, where the gate is re-evaluated on every
      # attempt. A denied attempt then falls back to the password field, which
      # is the intended behaviour rather than a permanent capability loss.
      environment = {
        DMS_FORCE_FPRINT_AVAILABLE = "1";

        # The shell runs on the qtengine Qt platform theme rather than the
        # session's gtk3 one. Tray icons are resolved by Qt's own icon loader,
        # and gtk3 only reports an icon theme once, at startup (from
        # settings.ini, which home-manager no longer writes it to), so the tray
        # neither followed the light/dark switch nor found Papirus at all.
        # qtengine watches ~/.config/qtengine/config.json, which DMS rewrites
        # with the per-mode icon theme on every transition. Only this unit:
        # other Qt apps stay on gtk3. See docs/theme.md.
        QT_QPA_PLATFORMTHEME = "qtengine";
        QT_QPA_PLATFORMTHEME_QT6 = "qtengine";
        # Replaces the inherited value, so the user profile is spelled out
        # again (%u expands to the user name in a user unit).
        QT_PLUGIN_PATH = "${pkgs.unstable.qtengine}/lib/qt-6/plugins:/etc/profiles/per-user/%u/lib/qt-6/plugins";
      };

      serviceConfig.ExecStartPre = pkgs.writeShellScript "dms-wait-for-wayland" ''
        for _ in $(${pkgs.coreutils}/bin/seq 100); do
          [ -n "''${WAYLAND_DISPLAY:-}" ] \
            && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] \
            && exit 0
          ${pkgs.coreutils}/bin/sleep 0.1
        done
        # Fall through and let the shell fail properly: Restart=on-failure will
        # retry.
        exit 0
      '';
    };

    # Hand the power button's short press to DMS's power menu. logind would
    # otherwise power off on its own the moment the key goes down — it acts on
    # the evdev event itself, before (and regardless of) any compositor bind,
    # and DMS takes no `handle-power-key` inhibitor that would stop it. With
    # logind ignoring it, the press reaches Hyprland as XF86PowerOff and the
    # bind there calls `dms ipc call powermenu toggle`.
    #
    # The long press stays with logind, so holding the button still powers off
    # when the shell is wedged, while locked, or at the greeter — none of which
    # can open the menu (the bind is not `locked`, and the greeter has no
    # Hyprland session at all).
    services.logind.settings.Login = {
      HandlePowerKey = "ignore";
      HandlePowerKeyLongPress = "poweroff";
    };

    # The lock screen's password stack. DMS generates a PAM config under
    # ~/.local/state by default; settings.lockPamExternallyManaged points it at
    # /etc/pam.d/dankshell instead, so the factors and their ordering are
    # declared here like any other NixOS PAM service. Two things depend on it:
    #
    #  * gnome-keyring. greetd autologs in, so no password ever reaches the
    #    login stack; pam_gnome_keyring's auth handler forwards the one typed
    #    at the lock gate to the already-running daemon.
    #  * dedsm.fingerprintPolicy's password clock, which is refreshed by the
    #    pam_exec stamp that module appends to every service in
    #    `passwordServices` — `dankshell` among them. Without this stack DMS
    #    would authenticate against its own user-level config, no stamp would
    #    ever be written, and the policy would drift into permanent denial.
    #
    # No pam_fprintd here: the sensor is driven by DMS's own parallel PAM
    # context off its bundled stack, which keeps it live alongside the password
    # field rather than blocking the conversation ahead of pam_unix. That
    # context is suppressed when settings.lockPamExternallyManaged is set, which
    # is why that setting is off — see the note in the home-manager dms module.
    # Either way the sensor goes through fprintd, so dedsm.fingerprintPolicy
    # governs it.
    security.pam.services.dankshell = {
      enableGnomeKeyring = true;
      fprintAuth = false;
    };

    # DMS asks GeoClue2 for the sunrise/sunset times behind its automatic
    # light/dark schedule, under the desktop id "dms"
    # (core/internal/geolocation/client_geoclue.go). GeoClue denies desktop ids
    # it has no entry for, and DMS then falls back to IP geolocation with only
    # a log line — so this is what keeps the schedule as accurate as darkman's
    # was. `dedsm.gnome-services` is what actually enables geoclue2.
    services.geoclue2.appConfig.dms = {
      isAllowed = true;
      isSystem = true;
    };

    # `dms setup` and the greeter installers write compositor configs and
    # system units directly, which on this host are generated by Nix. DMS reads
    # this policy file and refuses those commands outright when the system is
    # declared immutable, which turns "don't run that" into something enforced.
    environment.etc."dms/cli-policy.json".text = builtins.toJSON {
      policy_version = 1;
      immutable_system = true;
      blocked_commands = [
        "setup"
        "greeter install"
        "greeter enable"
        "greeter uninstall"
      ];
      message = "This system is managed by Nix — change modules/nixos/dms instead.";
    };

    # The screen-recording picker (`dms-screencast` in the home-manager dms
    # module) records regions and monitors off KMS, which takes CAP_SYS_ADMIN.
    # This installs gsr-kms-server as a setcap wrapper in /run/wrappers/bin,
    # where the nixpkgs gpu-screen-recorder looks for it first; without it every
    # region or monitor recording would stop at a pkexec password prompt. The
    # trade-off is that any local process — even one with no Wayland socket —
    # can read the screen through it. On a single-user laptop that adds little
    # to what Hyprland's screencopy already gives every Wayland client. Window
    # recording goes through the portal and needs none of this.
    programs.gpu-screen-recorder.enable = true;

    # DMS points the `gtk-theme` dconf key at adw-gtk3/adw-gtk3-dark, and
    # patches a copy of the theme into ~/.local/share/themes. Without the theme
    # installed that key names something that doesn't exist and GTK3 apps fall
    # back to raw defaults.
    environment.systemPackages = [
      pkgs.adw-gtk3

      # `pactl`, for the control centre's audio card handling: sink ports,
      # profiles, and the Bluetooth codec selector, which all shell out to it
      # (AudioService.qml). PipeWire provides the Pulse *server*
      # (`services.pipewire.pulse.enable`) but not the client tools, and
      # `services.pulseaudio.enable = false` keeps the package off PATH — so
      # without this the codec dropdown reports "pactl was not found". Only the
      # binaries are used; nothing here starts a second sound server.
      pkgs.pulseaudio
    ];
  };
}
