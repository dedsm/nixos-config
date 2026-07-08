{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.onepassword;
in {
  options.dedsm.onepassword = {
    enable = mkOption {
      description = "1Password CLI + GUI";
      type = with types; bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    environment.etc."1password/custom_allowed_browsers" = {
      text = ''
        firefox-devedition
      '';
      mode = "0755";
    };

    programs._1password = {
      enable = true;
      package = pkgs.unfree._1password-cli;
    };
    programs._1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "david" ];
      package = pkgs.unfree._1password-gui;
    };
  };
}
