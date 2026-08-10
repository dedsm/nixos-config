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

  recheck = {
    epoch = 1788912000;
    date = "2026-09-09";
  };
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
    };

    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];

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
