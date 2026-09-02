{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.dedsm.fingerprintPolicy;

  # /run is a tmpfs, so "no state" and "nothing since the last boot" are the
  # same thing — that is the "password after a restart" condition, for free,
  # with nothing to reset and nothing to forget.
  stateDir = "/run/fingerprint-policy";
  passwordStamp = "${stateDir}/password-auth";
  fprintStamp = "${stateDir}/fingerprint-unlock";
  failures = "${stateDir}/failures";
  group = "fingerprint-policy";

  # One window for the machine rather than one per user, deliberately. The
  # polkit subject is the *calling process*, and pam_fprintd runs inside sudo,
  # which is root — so a per-user window would ask for root's stamp on a sudo
  # fingerprint while sudo's own PAM stack wrote david's.

  # Reads the counter into $n. The file is only ever replaced atomically, so
  # unreadable content is not a torn write — it is a broken invariant, and
  # `unreadable` says what that costs the caller.
  readFailures = unreadable: ''
    if n=$(${pkgs.coreutils}/bin/cat ${failures} 2>/dev/null); then
      case "$n" in
        "" | *[!0-9]*) ${unreadable} ;;
      esac
    else
      # Not written yet this boot: nothing has failed.
      n=0
    fi
  '';

  # Both clocks, as seconds-since. $sincePw is always valid past this point;
  # $sinceFp is -1 for "never" — which includes a stamp dated in the future,
  # because a backwards clock step (an NTP correction, a bad RTC across a
  # suspend) leaves elapsed time not worth handing a security decision to.
  readClocks = missingPassword: ''
    now=$(${pkgs.coreutils}/bin/date +%s)

    pw=$(${pkgs.coreutils}/bin/stat -c %Y ${passwordStamp} 2>/dev/null) || { ${missingPassword}; }
    sincePw=$(( now - pw ))
    [ "$sincePw" -ge 0 ] || { ${missingPassword}; }

    if fp=$(${pkgs.coreutils}/bin/stat -c %Y ${fprintStamp} 2>/dev/null); then
      sinceFp=$(( now - fp ))
      [ "$sinceFp" -ge 0 ] || sinceFp=-1
    else
      sinceFp=-1
    fi

    sinceUnlock=$sincePw
    if [ "$sinceFp" -ge 0 ] && [ "$sinceFp" -lt "$sinceUnlock" ]; then
      sinceUnlock=$sinceFp
    fi
  '';

  # Spawned by the polkit rule below. Prints "yes" while fingerprint auth is
  # permitted, "no" otherwise. Always exits 0: polkit.spawn turns a non-zero
  # exit into a JS exception, and an exception must not be the only thing
  # standing between a stale window and a granted fingerprint (the rule treats
  # one as "no" too, but this is not the place to lean on that).
  gate = pkgs.writeShellScript "fingerprint-gate" ''
    deny() { echo no; exit 0; }

    ${readClocks "deny"}

    # No unlock of any kind for too long.
    [ "$sinceUnlock" -lt ${toString cfg.maxTimeSinceUnlock} ] || deny

    # No password for too long *and* no fingerprint unlock recently enough to
    # extend it. A grace of 0 makes the password interval a hard cap.
    if [ "$sincePw" -ge ${toString cfg.maxTimeSincePassword} ]; then
      [ "$sinceFp" -ge 0 ] || deny
      [ "$sinceFp" -lt ${toString cfg.fingerprintGrace} ] || deny
    fi
    ${optionalString (cfg.failureLimit > 0) ''
      ${readFailures "deny"}
      [ "$n" -lt ${toString cfg.failureLimit} ] || deny
    ''}

    echo yes
  '';

  # pam_exec target for a successful password authentication.
  #
  # It does *not* run as root for every service: hyprlock is an ordinary user
  # process running its own PAM conversation, so its stack — the one that
  # matters most here — executes this as the user. Hence the group-writable,
  # setgid state directory. Anything running as that user could therefore forge
  # a stamp, which is inherent rather than a shortcut: the unlock signal itself
  # originates inside a process that user controls. It buys nothing against the
  # attacker this policy is for — someone holding a locked laptop, with no code
  # running as its owner.
  stampScript = pkgs.writeShellScript "fingerprint-policy-stamp" ''
    [ "''${PAM_TYPE:-}" = "auth" ] || exit 0

    # Group-writable so both root's stacks (sudo, login, greetd) and the
    # user's (hyprlock) can refresh it; the group comes from the setgid
    # directory. World-readable because polkitd runs the gate as itself.
    ${pkgs.coreutils}/bin/install -m 0664 /dev/null ${passwordStamp}
    ${optionalString (cfg.failureLimit > 0) ''
      # Written, not truncated: to the gate an empty counter is a broken
      # invariant, and it fails closed on one.
      ${pkgs.coreutils}/bin/printf '0' > ${failures}.pam
      ${pkgs.coreutils}/bin/chmod 0664 ${failures}.pam
      ${pkgs.coreutils}/bin/mv -f ${failures}.pam ${failures}
    ''}
  '';

  # pam_exec target for the *session* stack of whatever opens the graphical
  # session: logging out drops every clock, so the next login is a password
  # one. Only session-opening services get this — a tty login closing its
  # session must not revoke the window under a running desktop.
  clearScript = pkgs.writeShellScript "fingerprint-policy-clear" ''
    [ "''${PAM_TYPE:-}" = "close_session" ] || exit 0
    ${optionalString (cfg.users != [ ]) ''
      # Only a *human* logging out counts. greetd runs its greeter through the
      # same PAM service as the session it starts, so tuigreet's own session
      # closing would otherwise land here — right after the password typed
      # into it had refreshed the clock, and wipe it.
      case "''${PAM_USER:-}" in
        ${concatMapStringsSep " | " (u: ''"${u}"'') cfg.users}) ;;
        *) exit 0 ;;
      esac
    ''}
    ${pkgs.coreutils}/bin/rm -f ${passwordStamp} ${fprintStamp} ${failures}
  '';

  # The same checks as the gate, phrased for a human. Silent when fingerprint
  # auth is available, so it can be dropped straight into a hyprlock label:
  # there is nothing to say while the reader works, and hyprlock's own
  # $FPRINTPROMPT covers that case anyway. `-v` also reports the open case,
  # with the tightest clock, for asking from a terminal.
  status = pkgs.writeShellScriptBin "fingerprint-status" ''
    say() { echo "$1"; exit 0; }

    ${readClocks ''say "Password required — no unlock since boot"''}

    [ "$sinceUnlock" -lt ${toString cfg.maxTimeSinceUnlock} ] ||
      say "Password required — not unlocked in over ${toString (cfg.maxTimeSinceUnlock / 3600)}h"

    left=$(( ${toString cfg.maxTimeSincePassword} - sincePw ))
    if [ "$left" -le 0 ]; then
      [ "$sinceFp" -ge 0 ] && [ "$sinceFp" -lt ${toString cfg.fingerprintGrace} ] ||
        say "Password required — over ${
          toString (cfg.maxTimeSincePassword / 3600)
        }h since your password"
      # Riding the grace period: what is left is the grace, not the password
      # interval that already lapsed.
      left=$(( ${toString cfg.fingerprintGrace} - sinceFp ))
    fi
    ${optionalString (cfg.failureLimit > 0) ''
      ${readFailures ''say "Password required — too many failed fingerprint attempts"''}
      [ "$n" -lt ${toString cfg.failureLimit} ] ||
        say "Password required — too many failed fingerprint attempts"
    ''}

    idleLeft=$(( ${toString cfg.maxTimeSinceUnlock} - sinceUnlock ))
    [ "$idleLeft" -lt "$left" ] && left=$idleLeft

    [ "''${1:-}" = "-v" ] && echo "Fingerprint available for $(( left / 3600 ))h$(( left % 3600 / 60 ))m"
    exit 0
  '';

  # polkit only ever sees an attempt *start*, never how it ended, and counting
  # VerifyStart calls would be wrong: a resume issues one without anyone having
  # touched the sensor. The result comes from fprintd's VerifyStatus signal
  # instead, which it broadcasts and whose D-Bus policy does not restrict who
  # may receive it — so this needs no monitor privileges, just a match rule.
  # stdbuf matters: without it glib's stdio sits on the lines in the pipe.
  monitor = pkgs.writeShellScript "fingerprint-failure-monitor" ''
    write() {
      ${pkgs.coreutils}/bin/printf '%s' "$1" > ${failures}.new
      ${pkgs.coreutils}/bin/chmod 0664 ${failures}.new
      ${pkgs.coreutils}/bin/mv -f ${failures}.new ${failures}
    }

    ${pkgs.coreutils}/bin/stdbuf -oL \
      ${pkgs.glib.bin}/bin/gdbus monitor --system --dest net.reactivated.Fprint |
      while IFS= read -r line; do
        case "$line" in
          *VerifyStatus*"'verify-no-match'"*)
            ${readFailures "n=0"}
            n=$(( n + 1 ))
            write "$n"
            echo "failed match $n/${toString cfg.failureLimit}" >&2
            ;;
          *VerifyStatus*"'verify-match'"*)
            # Any successful match, which includes a sudo one — close enough
            # to "the fingerprint unlocked it", and the permissive direction.
            ${pkgs.coreutils}/bin/install -m 0664 /dev/null ${fprintStamp}
            write 0
            ;;
        esac
      done
  '';

  # NixOS generates `auth sufficient pam_unix.so`, and `sufficient` returns
  # from the stack the moment it succeeds — anything appended after it never
  # runs on the one path we care about. Rewrite that one control so a
  # successful password falls through to the stamp and then to pam_permit,
  # while every failure still terminates the stack:
  #
  #   success          -> ok    (continue to the stamp)
  #   new_authtok_reqd -> done  (as `sufficient` did: return, do not stamp)
  #   anything else    -> die   (fail now, as falling through to pam_deny did)
  #
  # Orders are relative to pam_unix's own, per the warning on the `order`
  # option: the built-in values differ per service (sudo's stack is packed
  # tighter than hyprlock's) and are explicitly not stable.
  stampService = service: {
    ${service}.rules.auth =
      let
        unixOrder = config.security.pam.services.${service}.rules.auth.unix.order;
      in
      {
        unix.control = mkForce "[success=ok new_authtok_reqd=done default=die]";
        fingerprint-policy-stamp = {
          order = unixOrder + 10;
          control = "optional";
          modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
          args = [
            "quiet"
            "${stampScript}"
          ];
        };
        fingerprint-policy-permit = {
          order = unixOrder + 20;
          control = "sufficient";
          modulePath = "${pkgs.pam}/lib/security/pam_permit.so";
        };
      };
  };

  clearOnLogout = service: {
    ${service}.rules.session.fingerprint-policy-clear = {
      order = config.security.pam.services.${service}.rules.session.unix.order + 10;
      control = "optional";
      modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
      args = [
        "quiet"
        "${clearScript}"
      ];
    };
  };
in
{
  options.dedsm.fingerprintPolicy = {
    enable = mkOption {
      description = ''
        Time and failure limits on fingerprint auth, enforced for every fprintd
        consumer at once. Modelled on the conditions Apple documents for Touch
        ID; see docs/login-flow.md for the mapping.
      '';
      type = with types; bool;
      default = false;
    };

    maxTimeSinceUnlock = mkOption {
      description = ''
        Seconds without *any* unlock — password or fingerprint — after which a
        password is required. Apple's equivalent is 48 hours.
      '';
      type = with types; ints.positive;
      default = 48 * 60 * 60;
    };

    maxTimeSincePassword = mkOption {
      description = ''
        Seconds since the last password authentication after which a password
        is required again, unless `fingerprintGrace` is still running.
        Apple's equivalent is 156 hours (six and a half days).
      '';
      type = with types; ints.positive;
      default = 156 * 60 * 60;
    };

    fingerprintGrace = mkOption {
      description = ''
        Once `maxTimeSincePassword` has lapsed, seconds after a *fingerprint*
        unlock during which the reader still works — so continued use extends
        itself, up to `maxTimeSinceUnlock`. Apple's equivalent is 4 hours.
        0 makes `maxTimeSincePassword` a hard cap.
      '';
      type = with types; ints.unsigned;
      default = 4 * 60 * 60;
    };

    failureLimit = mkOption {
      description = ''
        Consecutive failed matches after which fingerprint auth is withdrawn
        until the next password authentication. Apple's equivalent is 5.
        0 disables the counter, and the service that keeps it.
      '';
      type = with types; ints.unsigned;
      default = 5;
    };

    passwordServices = mkOption {
      description = ''
        PAM services whose successful password authentication refreshes the
        password clock. Each needs a `unix` rule in its auth stack.
      '';
      type = with types; listOf str;
      default = [
        "hyprlock"
        "sudo"
        "login"
        "greetd"
      ];
    };

    sessionServices = mkOption {
      description = ''
        PAM services whose session *closing* clears every clock, so that a
        logout forces a password — Apple's "the user has logged out of their
        Mac account". Only whatever opens the desktop session belongs here: a
        tty login ending must not revoke the window under a running desktop.
      '';
      type = with types; listOf str;
      default = [ "greetd" ];
    };

    users = mkOption {
      description = ''
        Users whose PAM stacks run unprivileged and therefore need write
        access to the state — in practice, whoever runs the screen locker,
        since a locker authenticates as itself rather than as root. Without
        this their password unlock cannot refresh the clock, and the reader
        stays off (`fingerprint-status` says so).
      '';
      type = with types; listOf str;
      default = [ ];
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.fprintd.enable;
        message = "dedsm.fingerprintPolicy gates fprintd, which is not enabled.";
      }
      {
        assertion = config.security.polkit.enable;
        message = "dedsm.fingerprintPolicy is enforced by a polkit rule, and polkit is disabled.";
      }
      {
        assertion = cfg.fingerprintGrace < cfg.maxTimeSinceUnlock;
        message = "dedsm.fingerprintPolicy.fingerprintGrace is longer than maxTimeSinceUnlock, which can never be reached.";
      }
    ];

    users.groups.${group} = { };
    users.users = genAttrs cfg.users (_: {
      extraGroups = [ group ];
    });

    # setgid, so a file written by the user's locker still lands in the shared
    # group and stays rewritable by root's stacks (and the other way round).
    systemd.tmpfiles.rules = [ "d ${stateDir} 2775 root ${group} -" ];

    # Read by the hyprlock label (via /run/current-system/sw/bin) and handy
    # from a shell: `fingerprint-status -v`.
    environment.systemPackages = [ status ];

    security.pam.services = mkMerge (
      map stampService cfg.passwordServices ++ map clearOnLogout cfg.sessionServices
    );

    # The gate. fprintd checks polkit on *every* invocation of a method that
    # needs a permission, and caches nothing for a NO. VerifyStart needs
    # `verify` — so this is re-evaluated on each attempt and on each resume,
    # including for a locker that has been up since before the clocks lapsed.
    #
    # `enroll` has to be denied alongside `verify`, and not because enrolling
    # matters here: Claim requires verify *or* enroll, and fprintd's check
    # returns on the first permission that authorizes. Deny only verify and a
    # locker's Claim falls through to enroll, whose default is auth_self_keep
    # — with ALLOW_USER_INTERACTION set, that pops an agent dialog underneath
    # the lock screen.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id != "net.reactivated.fprint.device.verify" &&
            action.id != "net.reactivated.fprint.device.enroll")
          return polkit.Result.NOT_HANDLED;
        try {
          if (polkit.spawn(["${gate}"]).trim() == "yes")
            return polkit.Result.NOT_HANDLED; // fprintd's own defaults apply
        } catch (e) {
          polkit.log("fingerprint-policy: gate failed, denying: " + e);
        }
        return polkit.Result.NO;
      });
    '';

    systemd.services.fingerprint-failure-monitor = mkIf (cfg.failureLimit > 0) {
      description = "Track fingerprint match results for dedsm.fingerprintPolicy";
      wantedBy = [ "multi-user.target" ];
      after = [ "dbus.service" ];
      # Nothing to reconcile on restart: the state is files in /run, and a
      # missed signal only ever fails open (the clocks still apply).
      serviceConfig = {
        ExecStart = "${monitor}";
        Restart = "always";
        RestartSec = 2;
        # Reads one bus, writes two files.
        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ stateDir ];
        RestrictAddressFamilies = "AF_UNIX";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
      };
    };
  };
}
