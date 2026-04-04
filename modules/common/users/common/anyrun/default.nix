{
  lib,
  homeManagerConfig,
  anyrun,
  pkgs,
  ...
}:
with lib;
let
  anyrunPkgs = anyrun.packages.${pkgs.system};
in
  mkIf (homeManagerConfig.anyrun.enable or false) {
    programs.anyrun = {
      enable = true;
      config = {
        x = { fraction = 0.5; };
        y = { fraction = 0.3; };
        width = { fraction = 0.3; };
        hideIcons = false;
        ignoreExclusiveZones = false;
        layer = "overlay";
        closeOnClick = true;
        showResultsImmediately = true;
        maxEntries = 10;
        plugins = [
          anyrunPkgs.applications
          anyrunPkgs.actions
          anyrunPkgs.translate
          anyrunPkgs.rink
          anyrunPkgs.shell
        ];
      };
      extraConfigFiles."actions.ron".text = ''
        Config(
          enable_power_actions: true,
          custom_actions: [],
        )
      '';
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
