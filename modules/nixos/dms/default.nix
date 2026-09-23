{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.dedsm.dms;

  # Seconds pam_fprintd waits for a finger before it gives up on one verify.
  #
  # Upstream's bundled stack (`assets/pam/fprint`, the one DMS's parallel
  # fingerprint context runs) passes no `timeout=`, so pam_fprintd uses its own
  # default of 30s and then returns PAM_AUTHINFO_UNAVAIL. DMS reads that as
  # `PamResult.Error` and re-arms on an exponential backoff —
  # `Math.min(1500 * 2^(errorTries - 1), 30000)` in Modules/Lock/Pam.qml — whose
  # counter is only reset by `checkAvail()`, which runs when the lock *opens*
  # and on a settings change, never on wake or on activity. So within about two
  # minutes of a lock the backoff saturates and the reader settles into 30s
  # armed, 30s dead, forever: touching the sensor is a coin flip, which is
  # exactly what "the fingerprint is unreliable" looks like from the outside.
  #
  # The longer per-attempt timeout is the load-bearing half of the fix, because
  # it removes the *error* rather than the response to one. 10 minutes takes the
  # duty cycle from 50% to 95%. The timer restarts after each no-match, so with
  # `max-tries=5` a context can live up to 50 minutes.
  #
  # What it costs: the polkit gate is checked on `VerifyStart`, so an attempt
  # armed just before a fingerprint-policy window lapses stays valid until it
  # ends — a tail of at most this long on windows measured in 48 and 156 hours.
  # See docs/login-flow.md.
  #
  # Not `timeout=-1`, which pam_fprintd(8) documents as "always active while
  # this module is loaded" and which would otherwise be the exact fit: with no
  # timeout there is never a second `VerifyStart`, so on a machine nobody
  # touches the gate would be consulted once at lock time and never again, and
  # a laptop locked before the window lapsed would keep accepting fingerprints
  # straight through it. A bounded tail is the whole point.
  fprintTimeout = 600;

  # Milliseconds the backoff above is allowed to reach, replacing upstream's
  # 30000. The sequence becomes 1.5s, 3s, 3s, … between `fprintTimeout`-long
  # armed windows: a 99.5% duty cycle rather than 95%, and no 30-second hole an
  # hour into a lock.
  #
  # This is only safe *together* with the long timeout. On its own it would be a
  # downgrade: the retry budget is 200 per lock cycle (`errorTries < 200`,
  # Pam.qml), and at upstream's 30s timeout a 3s cap spends all 200 in under two
  # hours, so a laptop locked over lunch comes back with the reader switched off
  # entirely. At 600s per attempt the same 200 covers ~33 hours, past the point
  # `dedsm.fingerprintPolicy.maxTimeSinceUnlock` demands a password anyway.
  #
  # The budget does burn faster in the one case that fails *instantly* — a gate
  # denial, or a missing reader — where 200 retries now take ~10 minutes instead
  # of ~1.7 hours. Nothing is lost by giving up sooner there: within a single
  # lock cycle a denial is monotonic. Both clocks only move forward, and the
  # failure counter is cleared only by a password authentication, which ends the
  # lock. There is no state to wait around for.
  #
  # Anchored to an arithmetic expression in a QML file, so it is the fragile
  # half of this override — `--replace-fail` turns an upstream edit into a build
  # failure rather than a silent no-op, which is the intended outcome.
  fprintRetryCapMs = 3000;
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
      # 26.05 ships 1.4.6; unstable is 1.6.2. Upstream's own flake runs ahead,
      # but mixing its package with this module drops some dependency wiring,
      # so track nixpkgs on both.
      #
      # Two patches on top, both aimed at the lock screen's fingerprint path:
      # a `timeout=` on the bundled PAM stack, and a shorter cap on the retry
      # backoff that timeout feeds. See the comments on `fprintTimeout` and
      # `fprintRetryCapMs` above, and docs/dms.md.
      #
      # These patch the *source* tree and re-run `make sync-shell`, rather than
      # editing the installed tree. As of 1.6.x the QML shell is baked into the
      # Go binary — nixpkgs builds with the `withshell` tag, and `sync-shell`
      # copies `quickshell/` into `core/internal/shellembed/dist` for `go:embed`
      # — so `$out/share/quickshell` no longer exists and a postInstall
      # substitution has nothing to bite on. `sync-shell` is `rm -rf` plus a
      # fresh copy, so re-running it after the edits is safe and, importantly,
      # recomputes the `.dankrev` content hash the shell keys its extracted
      # copy on; patching the embed dir in place would leave that stale.
      package = pkgs.unstable.dms-shell.overrideAttrs (old: {
        preBuild = (old.preBuild or "") + ''
          substituteInPlace ../quickshell/assets/pam/fprint \
            --replace-fail 'max-tries=' 'timeout=${toString fprintTimeout} max-tries='

          substituteInPlace ../quickshell/Modules/Lock/Pam.qml \
            --replace-fail \
              'Math.min(1500 * Math.pow(2, Math.max(0, fprint.errorTries - 1)), 30000)' \
              'Math.min(1500 * Math.pow(2, Math.max(0, fprint.errorTries - 1)), ${toString fprintRetryCapMs})'

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
      environment.DMS_FORCE_FPRINT_AVAILABLE = "1";

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
