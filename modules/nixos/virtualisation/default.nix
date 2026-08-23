{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.dedsm.virtualisation;
in
{
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
      daemon.settings = {
        # Default pools carve too few subnets (bridges already span all of 172.17-172.31/16
        # on this host, exhausting 172.16.0.0/12 entirely); /24s over an unused 10.x block
        # instead of the default /16 per network raise that ceiling by orders of magnitude.
        default-address-pools = [
          {
            base = "10.100.0.0/14";
            size = 24;
          }
        ];
      };
    };
  };
}
