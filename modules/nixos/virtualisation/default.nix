{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.virtualisation;
in {
  options.dedsm.virtualisation = {
    enable = mkOption {
      description = "Docker";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      package = pkgs.unstable.docker;
      liveRestore = false;
      enableOnBoot = false; # Don't start Docker on boot - start on-demand via socket activation
    };
  };
}
