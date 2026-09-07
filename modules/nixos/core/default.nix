{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.dedsm.core;
in
{
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
    # The ESP is 510 MiB and a generation costs a 14 MiB kernel plus a 62-69 MiB
    # systemd initrd — call it 80 MiB whenever the initrd differs, which it does
    # for a kernel bump, a firmware change, or anything baked into the initrd
    # (enabling plymouth added 7 MiB to it). Twenty entries therefore cannot fit:
    # six distinct initrds already fill the partition, and a run of rebuilds in
    # one evening is exactly the case that overflows it. Five leaves headroom for
    # the boot menu to be useful without ever wedging a rebuild.
    #
    # This only bounds the *menu*. Older generations stay on disk and remain
    # reachable with `nixos-rebuild switch --rollback` from a running system;
    # what the limit protects is the ability to boot at all.
    boot.loader.systemd-boot.configurationLimit = 5;
    boot.loader.efi.canTouchEfiVariables = true;

    # A splash from the initrd through to the greeter, so the boot never shows
    # the console. greetd is aliased to display-manager.service and ordered
    # After=plymouth-quit-wait.service by its NixOS module, so the splash holds
    # until the greeter is ready to draw: splash -> greeter -> session, with no
    # VT text in between. (`services.greetd.greeterManagesPlymouth` would hand
    # over without even a black frame, but that needs a greeter that quits
    # plymouth itself, and dank-greeter has no plymouth support at all.)
    #
    # This also moves the LUKS passphrase prompt into plymouth. If it ever
    # misbehaves, removing `quiet` at the boot menu brings the console back.
    boot.plymouth.enable = true;
    # `quiet` and loglevel silence the kernel; show_status silences systemd's own
    # "Starting/Started ..." lines, which are what otherwise appear on the VT in
    # the moment between the greeter exiting and the session's compositor taking
    # the display.
    boot.kernelParams = [
      "quiet"
      "systemd.show_status=false"
    ];
    boot.initrd.verbose = false;
    boot.consoleLogLevel = 0;
    i18n = {
      defaultLocale = cfg.defaultLocale;
    };

    networking.networkmanager = {
      enable = true;
      wifi.backend = "wpa_supplicant";
      plugins = with pkgs; [ networkmanager-openvpn ];
    };
    systemd.services.NetworkManager-wait-online.enable = false;

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

    environment.enableAllTerminfo = true;
    environment.systemPackages = with pkgs; [
      git
      any-nix-shell
      nixfmt
      qt5.qtwayland
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

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    nix.settings.auto-optimise-store = true;

    # Automatic garbage collection of old generations. This prunes the system
    # profile generations (which home-manager is embedded in via
    # useUserPackages), so it reclaims old home closures too. Active dev shells
    # pinned by direnv gcroots are always protected regardless of age.
    nix.gc = {
      automatic = true;
      dates = "weekly";
      randomizedDelaySec = "30min";
      options = "--delete-older-than 30d";
    };
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
