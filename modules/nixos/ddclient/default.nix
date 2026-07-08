{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.ddclient;
in {
  options.dedsm.ddclient = {
    enable = mkOption {
      description = "Dynamic DNS updates (ddclient)";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    services.ddclient = {
      enable = true;
      # Kept outside the repo tree on purpose: /etc/nixos may be a symlink to
      # this (public) flake, so a repo-relative path would risk committing the
      # dynamic-DNS credentials. /var/lib/ddclient is machine-local state.
      configFile = "/var/lib/ddclient/ddclient.conf";
    };
  };
}
