{ lib, ... }:
{
  imports = [ ./common ];

  options.dedsm.defaults.enable = lib.mkEnableOption "the Linux desktop defaults (Firefox, foot, cursor theme)";
}
