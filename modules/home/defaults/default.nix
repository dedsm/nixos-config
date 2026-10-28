{ lib, ... }:
{
  imports = [ ./settings.nix ];

  options.dedsm.defaults.enable = lib.mkEnableOption "the Linux desktop defaults (Firefox, foot, cursor theme)";
}
