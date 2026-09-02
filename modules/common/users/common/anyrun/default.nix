{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
with lib;
let
  anyrunPkg = pkgs.unstable.anyrun;
in
mkIf (homeManagerConfig.anyrun.enable or false) {
  # anyrun has needed a daemon since 25.12.0; upstream's own home-manager module
  # defaults it on, but the module we use (home-manager's built-in) has no option
  # for it, so the unit is declared here. Without it anyrun runs "standalone",
  # where it has no clipboard support, starts slower, and — the reason this exists
  # — writes a plugin's stdout result twice, which silently broke the hyprland
  # module's screenshot picker (anyrun-org/anyrun#324, open and unfixed as of
  # 26.6.1). The unit mirrors the one in upstream's module.
  systemd.user.services.anyrun = {
    Unit = {
      Description = "Anyrun daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${anyrunPkg}/bin/anyrun daemon";
      Restart = "on-failure";
      # Kept as upstream sets it: the daemon spawns an `anyrun-provider` child per
      # launch, and only the daemon itself is signalled on stop.
      KillMode = "process";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  programs.anyrun = {
    enable = true;
    package = anyrunPkg;

    # Config for the stdin plugin, which the hyprland module drives via `--plugins`
    # for its screenshot picker. Its own defaults cap an unfiltered list at 5 entries
    # and re-rank by fuzzy score, which hid the picker's sixth option until you typed
    # and shuffled the rest; keep every entry, in the order it was fed in.
    extraConfigFiles."stdin.ron".text = ''
      Config(
        max_entries: 20,
        preserve_order: true,
      )
    '';
    config = {
      x = {
        fraction = 0.5;
      };
      y = {
        fraction = 0.3;
      };
      width = {
        fraction = 0.3;
      };
      hideIcons = false;
      ignoreExclusiveZones = false;
      layer = "overlay";
      closeOnClick = true;
      showResultsImmediately = true;
      maxEntries = 10;
      plugins = [
        "${anyrunPkg}/lib/libapplications.so"
        "${anyrunPkg}/lib/libtranslate.so"
        "${anyrunPkg}/lib/librink.so"
        "${anyrunPkg}/lib/libshell.so"
      ];
    };
    extraCss = ''
      window {
        background: transparent;
      }

      box.main {
        background-color: rgba(250, 250, 250, 0.95);
        color: #1e1e1e;
        padding: 8px;
        margin: 10px;
        border-radius: 10px;
        border: 2px solid #3584e4;
        box-shadow: 0 0 8px rgba(0, 0, 0, 0.3);
      }

      text, text:focus {
        min-height: 30px;
        padding: 5px;
        border-radius: 5px;
        color: #1e1e1e;
        caret-color: #1e1e1e;
        background-color: rgba(0, 0, 0, 0.05);
      }

      .matches {
        background-color: transparent;
        border-radius: 10px;
      }

      box.plugin:first-child {
        margin-top: 5px;
      }

      list.plugin {
        background-color: transparent;
      }

      label.match {
        color: #1e1e1e;
      }

      label.match.description {
        font-size: 10px;
        color: #555555;
      }

      label.plugin.info {
        font-size: 14px;
        color: #1e1e1e;
      }

      .match {
        background: transparent;
      }

      .match:selected {
        border-left: 4px solid #3584e4;
        background: rgba(53, 132, 228, 0.1);
      }

      @media (prefers-color-scheme: dark) {
        box.main {
          background-color: rgba(30, 30, 30, 0.95);
          color: #eeeeee;
        }

        text, text:focus {
          color: #eeeeee;
          caret-color: #eeeeee;
          background-color: rgba(255, 255, 255, 0.08);
        }

        label.match {
          color: #eeeeee;
        }

        label.match.description {
          color: #aaaaaa;
        }

        label.plugin.info {
          color: #eeeeee;
        }

        .match:selected {
          background: rgba(53, 132, 228, 0.2);
        }
      }
    '';
  };
}
