{
  pkgs,
  config,
  lib,
  nixpkgs,
  ...
}:
with lib;
let
  cfg = config.dedsm.hyprland;

  quietSession = pkgs.writeTextFile {
    name = "hyprland-uwsm-quiet-session";
    destination = "/share/wayland-sessions/hyprland-uwsm-quiet.desktop";
    text = ''
      [Desktop Entry]
      Name=Hyprland (uwsm-managed, quiet)
      Comment=uwsm's startup output goes to the journal rather than the console
      Exec=${pkgs.systemd}/bin/systemd-cat --identifier=uwsm ${config.programs.uwsm.package}/bin/uwsm start -e -D Hyprland hyprland.desktop
      Type=Application
      DesktopNames=Hyprland
    '';
    derivationArgs.passthru.providedSessions = [ "hyprland-uwsm-quiet" ];
  };

  # --- Local backport of nixpkgs#532275, with an expiry ---------------------
  #
  # switch-to-configuration restarts *user* units whose definition changed.
  # uwsm's session units are booby-trapped for that: wayland-session-bindpid@
  # carries OnSuccess=wayland-session-shutdown.target (its whole job is to turn
  # "this went away" into "tear down the session"), so a rebuild that merely
  # rebuilds uwsm SIGKILLs the entire Hyprland session — including the
  # nixos-rebuild doing the switching, leaving the system half-activated.
  #
  # Upstream fixed this in nixpkgs#532275 (master, 2026-06-16) by setting
  # restartIfChanged = false on these units, exactly as the niri and
  # display-manager modules do. It was never backported to release-26.05, so
  # the block below is that fix, carried locally.
  #
  # The assertions further down are the expiry: eval fails the moment upstream
  # ships the fix (delete this) or the recheck date passes (go look again).
  uwsmModulePath = "${nixpkgs}/nixos/modules/programs/wayland/uwsm.nix";
  uwsmModuleFound = builtins.pathExists uwsmModulePath;
  uwsmFixedUpstream =
    uwsmModuleFound && hasInfix "restartIfChanged" (builtins.readFile uwsmModulePath);

  # Rechecked 2026-10-19: nixpkgs#532275 is merged upstream but still absent
  # from release-26.05 (`grep restartIfChanged` in the pinned uwsm.nix finds
  # nothing), so the backport stays and the date moves out another month.
  recheck = {
    epoch = 1794182400;
    date = "2026-11-09";
  };

  # --- xdg-desktop-portal-hyprland with upstream ba31964 --------------------
  #
  # The portal handed PipeWire consumers only the *first* plane of each
  # dma-buf. On this AMD iGPU the compositor's buffers use DCC modifiers, which
  # carry extra metadata planes, so every import failed: gpu-screen-recorder's
  # `-w portal` (the window entry of the dms screencast picker) logged "failed
  # to create egl image with modifier 0x2000000104abb04", renegotiated through
  # each DCC modifier in turn and died on "no more input formats". OBS and
  # browsers hit the same thing and quietly fall back to slow SHM copies.
  # ba31964 (gsr's author, merged 2026-08-29) sends every plane; it applies
  # cleanly to 1.3.12 and is in no xdph release yet — 1.4.1 predates it.
  xdphFix = pkgs.fetchpatch {
    name = "xdph-screencopy-all-dmabuf-planes.patch";
    url = "https://github.com/hyprwm/xdg-desktop-portal-hyprland/commit/ba31964ee42b56bcb0d3b78a64ead5d8a1c3c6f6.patch";
    hash = "sha256-K67rE3AXVLcuUMFs4ocG9dgihyIwabpGyPbbjz1zKTs=";
  };
  xdph = pkgs.xdg-desktop-portal-hyprland.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ xdphFix ];
  });
in
{
  options.dedsm.hyprland = {
    enable = mkOption {
      description = "System-level Hyprland session support";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    system.nixos.tags = [ "hyprland" ];

    programs.hyprland = {
      enable = true;
      withUWSM = true;
      # The module adds this to xdg.portal.extraPortals itself; listing the
      # stock package there as well would install a second, unpatched portal
      # under the same D-Bus name.
      portalPackage = xdph;
    };

    # A third session entry, identical to the uwsm one except that uwsm's
    # startup chatter goes to the journal instead of the console.
    #
    # greetd gives the session the VT it ran the greeter on, so whatever the
    # session's command writes to stdout lands on screen: "Selected compositor
    # ID", "Created unit subdir …", "Reloading systemd user manager", and so on.
    # That is the text visible between the login screen and Hyprland's first
    # frame — not kernel or systemd output, which is why `quiet`,
    # `systemd.show_status=false` and plymouth all leave it untouched. uwsm has
    # no quiet flag (`uwsm start --help`), so the redirect has to happen here.
    # In systemPackages as well as sessionPackages: the latter only reaches the
    # *user session's* XDG_DATA_DIRS, while the greeter scans the dirs its own
    # process has — which is where /run/current-system/sw/share is.
    services.displayManager.sessionPackages = [ quietSession ];
    environment.systemPackages = [ quietSession ];

    # See the comment above. Both units are defined with overrideStrategy at its
    # "asDropinIfExists" default, so this lands as a drop-in over uwsm's own
    # units. enableDefaultPath = false keeps the NixOS default PATH= out of that
    # drop-in, which would otherwise clobber the PATH uwsm imported into the
    # user manager and break `uwsm app` spawns.
    systemd.user.services = genAttrs [ "wayland-wm@" "wayland-session-bindpid@" ] (_: {
      restartIfChanged = false;
      enableDefaultPath = false;
    });

    assertions = [
      {
        assertion = versionOlder pkgs.xdg-desktop-portal-hyprland.version "1.4.2";
        message = ''
          dedsm.hyprland: xdg-desktop-portal-hyprland is now
          ${pkgs.xdg-desktop-portal-hyprland.version}, newer than the last release
          known to lack upstream ba31964 (send all dma-buf planes). If the new
          release includes it, remove every piece of the patch together:
            - xdphFix, xdph, portalPackage and this assertion in
              modules/nixos/hyprland/default.nix
            - the portalPackage line and its comment under
              wayland.windowManager.hyprland in
              modules/home/hyprland/default.nix
            - the ba31964 paragraph under "Screen recording" in docs/dms.md
          If not, raise the version in this assertion.
        '';
      }
      {
        assertion = uwsmModuleFound;
        message = ''
          dedsm.hyprland: ${uwsmModulePath} is gone, so the check for whether the
          local backport of nixpkgs#532275 is still needed cannot run. uwsm's
          NixOS module has moved or been renamed upstream: re-verify by hand that
          wayland-wm@/wayland-session-bindpid@ still get restartIfChanged = false
          from somewhere, then fix uwsmModulePath in
          modules/nixos/hyprland/default.nix.
        '';
      }
      {
        assertion = !uwsmFixedUpstream;
        message = ''
          dedsm.hyprland: the pinned nixpkgs now sets restartIfChanged on uwsm's
          session units itself — nixpkgs#532275 has landed on this channel. Drop
          the local backport (the systemd.user.services block) and these
          assertions from modules/nixos/hyprland/default.nix, and the "carried
          patch" section from docs/login-flow.md.
        '';
      }
      {
        assertion = nixpkgs.lastModified < recheck.epoch;
        message = ''
          dedsm.hyprland: the local backport of nixpkgs#532275 has been carried
          past ${recheck.date}. Check whether it reached release-26.05:

            gh pr list --repo NixOS/nixpkgs --state all --search 532275
            grep restartIfChanged ${uwsmModulePath}

          If it landed, the assertion above would have fired instead — so it
          hasn't. Either open the backport PR (merge commit a75cd823) or push
          recheck.epoch/date in modules/nixos/hyprland/default.nix out by another
          month.
        '';
      }
    ];
  };
}
