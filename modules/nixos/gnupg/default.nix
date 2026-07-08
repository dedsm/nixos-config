{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.gnupg;
in {
  options.dedsm.gnupg = {
    enable = mkOption {
      description = "GnuPG agent (with SSH support) instead of ssh-agent";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    programs.ssh.startAgent = false;
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryPackage = pkgs.pinentry-gnome3;
    };
  };
}
