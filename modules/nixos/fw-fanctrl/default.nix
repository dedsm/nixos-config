{
  pkgs,
  config,
  lib,
  overlaidPkgs,
  fw-fanctrl,
  ...
}:
with lib; let
  cfg = config.dedsm.fw-fanctrl;
in {
  options.dedsm.fw-fanctrl = {
    enable = mkEnableOption "Enable the fan control service";
  };

  config = mkIf cfg.enable {
    programs.fw-fanctrl = {
      enable = true;
      config = {
        defaultStrategy = "lazyest";
        strategies = {
          "lazyest" = {
            fanSpeedUpdateFrequency = 5;
            movingAverageInterval = 40;
            speedCurve = [
              { temp = 0; speed = 0; }
              { temp = 45; speed = 0; }
              { temp = 65; speed = 25; }
              { temp = 70; speed = 35; }
              { temp = 80; speed = 50; }
              { temp = 90; speed = 100; }
            ];
          };
        };
      };
    };
  };
}
