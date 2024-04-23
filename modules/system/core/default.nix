{ pkgs, config, lib, ... }:
with lib;
let cfg = config.dedsm.core;
in {
  options.dedsm.core = {
    timeZone = mkOption {
      description = "Time zone";
      type = with types; nullOr str;
      default = "Europe/Amsterdam";
    };

    defaultLocale = mkOption {
      description = "Default Locale";
      type = with types; nullOr str;
      default = "en_US.UTF-8";
    };
  };

  config = {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    i18n = { defaultLocale = cfg.defaultLocale; };

    time = {
      timeZone = cfg.timeZone;
      hardwareClockInLocalTime = false;
    };

    programs.zsh = {
      enable = true;
      enableCompletion = true;
    };
    users.defaultUserShell = pkgs.zsh;

    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    nix.settings.auto-optimise-store = true;
    networking.firewall.enable = false;

    # Enable the OpenSSH daemon.
    services.openssh.enable = true;

    services.accounts-daemon.enable = true;

    security.polkit.enable = true;
    security.rtkit.enable = true;
  };
}
