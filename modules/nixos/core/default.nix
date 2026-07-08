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

    networking.networkmanager = {
      enable = true;
      wifi.backend = "wpa_supplicant";
      plugins = with pkgs; [ networkmanager-openvpn ];
    };
    systemd.services.NetworkManager-wait-online.enable = false;

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      liberation_ttf
      fira-code
      fira-code-symbols
      dina-font
      proggyfonts
      pkgs.unstable.nerd-fonts.inconsolata-go
    ];

    services.xserver = {
      enable = true;
      xkb = {
        layout = "us";
        model = "pc105";
        variant = "altgr-intl";
        options = "caps:super";
      };
    };
    console.useXkbConfig = true;

    services.dbus = {
      enable = true;
      packages = [ pkgs.dconf ];
    };
    programs.dconf.enable = true;

    xdg = {
      mime.enable = true;
      icons.enable = true;
      portal = {
        enable = true;
        xdgOpenUsePortal = false;
        config.common.default = [ "gtk" ];
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      };
    };

    services.avahi = {
      enable = true;
      nssmdns4 = true;
    };

    # Audio
    services.pulseaudio.enable = false;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    home-manager.useGlobalPkgs = false;
    home-manager.useUserPackages = true;

    # Allowing compiled binaries to run if configured correctly
    programs.nix-ld.enable = true;

    security.pam.services.login.enableKwallet = true;

    environment.enableAllTerminfo = true;
    environment.systemPackages = with pkgs; [
      git
      any-nix-shell
      nixfmt
      qt5.qtwayland
      kdePackages.kwallet
      kdePackages.kwallet-pam
      ripgrep
      nodejs
      pnpm # Provides pnpm and pnpx
      lm_sensors
      inotify-tools
    ];

    time = {
      timeZone = mkIf (!config.services.automatic-timezoned.enable or false) cfg.timeZone;
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

    # Environment variables
    environment.variables = {
      VDPAU_DRIVER = "radeonsi";
    };

    services.accounts-daemon.enable = true;

    security.polkit.enable = true;
    security.rtkit.enable = true;

    # Aegis Local CA - private key has been deleted, safe to trust
    security.pki.certificates = [
      ''
        -----BEGIN CERTIFICATE-----
        MIIDEzCCAfugAwIBAgIUHaErDs5VmF4NS+nJXWJxfHT3mC8wDQYJKoZIhvcNAQEL
        BQAwGTEXMBUGA1UEAwwOQWVnaXMgTG9jYWwgQ0EwHhcNMjYwMzA4MTYyNTU3WhcN
        MjcwMzA4MTYyNTU3WjAZMRcwFQYDVQQDDA5BZWdpcyBMb2NhbCBDQTCCASIwDQYJ
        KoZIhvcNAQEBBQADggEPADCCAQoCggEBAKiMHA0dc5owm/Ia6zJ8SJckdJlexOB1
        +rmjkm4jZFp5BLH4P56zCy9uj/VTMPT78G8TY/7vY9tNc3xzkt6yDmW4z0IbAicy
        AzDX28zGcID2bhQeyN1Jy/jYAMEjz5hMUgunlbas3+K99rNU2KGk0KgK5L84Ub4+
        tOKmSkmKOw97LAP8PhOdRLmXHtbJMX8yNjU7w9dj0CHEDZdt4uJW7wThW4PRF8f8
        JxcnIIsmqFCxy81NIyAG6zGz+xDOgIZ3q17Em2tBQFbPE3IoYC6fq7HzsJLrtaVi
        NtN28xVQ7lqiibVcPie/TXU/D2BUHT8adMoVERAv5g652xuxlFfGiTECAwEAAaNT
        MFEwHQYDVR0OBBYEFJbd1Ka7yZfkV5BeNunzi/zpNW5jMB8GA1UdIwQYMBaAFJbd
        1Ka7yZfkV5BeNunzi/zpNW5jMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQEL
        BQADggEBABLL6JYzi5WW77jPazzMWLqyuTSfgkwzaK56bB0t2AE1ASRiE7kQ235g
        jcJMfqBfDfv7BPb3AIgYmqTkPkmL+7Sg6NZsoYyEpUY0EZIA+PoiUxu7JMIVEwWw
        iZYz5axg+ZHGDVrW+HZQ4RW9Nz93WY690DgxPGYNbx8crGE+pbB7QOFAL0HG0e9k
        zswGnXsk1SOTNkhU1QxxvL/Hr0IHj5FAG2KmXT+Xq0Rnc+TnbuzYCGkeqkVjglKE
        I4IeFxj5sowxitd7thb611Yii42t5TmQD/iuYQofqzvtySgni/GMp/dFZ00Ci7bR
        Y7lfqYCiQmGXURI0qAd8hkjaE9iumQk=
        -----END CERTIFICATE-----
      ''
    ];
  };
}
