{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.network-manager.enable {
  services.network-manager-applet.enable = true;
  systemd.user.services = {
    network-manager-applet = {
      Install = { WantedBy = lib.mkForce [ "sway-session.target" ]; };
      Unit = {
        After = lib.mkForce [ "sway-session.target" ];
        PartOf = lib.mkForce [ "sway-session.target" ];
        Requires = lib.mkForce [ "sway-session.target" ];
      };
      Service = { Restart = "Always"; };
    };
  };
}
