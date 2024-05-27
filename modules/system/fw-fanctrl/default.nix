{ pkgs, config, lib, overlaidPkgs, ... }:
with lib;
let 
  cfg = config.dedsm.fw-fanctrl;
  fw-fanctrl-nix = overlaidPkgs.fw-fanctrl-nix;
in {
  options.dedsm.fw-fanctrl = {
    enable = mkEnableOption "Enable the fan control service";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      overlaidPkgs.fw-fanctrl-nix
    ];

    powerManagement.powerDownCommands = ''
      ${fw-fanctrl-nix}/bin/fw-fanctrl --pause
    '';

    powerManagement.resumeCommands = ''
      ${fw-fanctrl-nix}/bin/fw-fanctrl --resume
    '';
    
    systemd.services.fw-fanctrl = {
      path = [ pkgs.fw-ectool ];
      description = "Fan control service for Framework";
      serviceConfig = {
        Restart = "on-failure";
        ExecStart = "${fw-fanctrl-nix}/bin/fw-fanctrl --run --config ${fw-fanctrl-nix}/config/config.json";
        ExecStopPost = "${pkgs.fw-ectool}/bin/ectool autofanctrl";
      };
      environment = {
        PYTHONUNBUFFERED = "1";
      };
      wantedBy = [ "multi-user.target" ];
    };

    systemd.tmpfiles.rules = [
      "D /run/fw-fanctrl 0755 root root - -"
    ];
  };
}
