{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
{
  options.dedsm.direnv = {
    enable = lib.mkEnableOption "direnv with nix-direnv";
  };

  config = lib.mkIf config.dedsm.direnv.enable {
    programs.direnv = {
      enable = true;
      package = pkgs.unstable.direnv;
      enableZshIntegration = true;
      nix-direnv.enable = true;
      config = {
        global = {
          warn_timeout = "3000h";
        };
      };
    };
  };
}
