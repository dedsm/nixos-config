{
  pkgs,
  user,
  ...
}: {
  imports = [
    # Add darwin specific modules here
    ./aerospace
  ];

  nix.optimise.automatic = true;

  # Automatic garbage collection of old generations. Home-manager is embedded in
  # the darwin system generation (useUserPackages), so pruning system
  # generations reclaims old home closures too. Active dev shells pinned by
  # direnv gcroots are always protected regardless of age. Note: launchd uses
  # `interval` (StartCalendarInterval), not systemd's `dates`.
  nix.gc = {
    automatic = true;
    interval = { Weekday = 0; Hour = 3; Minute = 0; };
    options = "--delete-older-than 30d";
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    max-jobs = 4;
    cores = 4;

    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  homebrew = {
    enable = true;
    global = {
      autoUpdate = false;
    };
    onActivation = {
      # Homebrew 5.x requires `--force-cleanup` for `brew bundle ... --cleanup` to
      # actually run; without it activation just prints usage and installs nothing.
      # nix-darwin doesn't pass it yet (see nix-darwin#1787 / PR #1789), so we inject
      # it via extraFlags to keep "zap" auto-removal working. NOTE: this will actively
      # uninstall (zap) any Homebrew package not declared above.
      cleanup = "zap";
      extraFlags = [ "--force-cleanup" ];
      autoUpdate = false;
      upgrade = false;
    };
    brews = [
      "cormacrelf/tap/dark-notify"
    ];
    casks = [
      "keepingyouawake"
      "logi-options+"
      "middleclick"
      "orbstack"
    ];
  };

  # Basic Darwin defaults
  system.defaults = {
    dock = {
      autohide = true;
      expose-group-apps = true;
    };
    screencapture = {
      location = "~/Downloads/";
    };
    spaces = {
      spans-displays = false;
    };
    finder = {
      AppleShowAllExtensions = true;
      CreateDesktop = false;
    };
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      AppleInterfaceStyleSwitchesAutomatically = true;
      AppleScrollerPagingBehavior = true;
      KeyRepeat = 4;
      "com.apple.keyboard.fnState" = true;
      "com.apple.trackpad.scaling" = 2.0;
      "com.apple.sound.beep.feedback" = 0;
    };

    WindowManager = {
      HideDesktop = true;
      StandardHideDesktopIcons = true;
    };

    trackpad = {
      TrackpadRightClick = true;
      Clicking = true;
      TrackpadThreeFingerDrag = false;
      TrackpadThreeFingerTapGesture = 2;
    };

    controlcenter = {
      BatteryShowPercentage = true;
      Bluetooth = true;
      Sound = true;
    };
  };

  system.startup.chime = false;

  system.primaryUser = user;

  programs.zsh.enable = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # this is broken now so manually installing for now
  # services.karabiner-elements = {
  #   enable = true;
  # };

  services.jankyborders = {
    enable = true;
    inactive_color = "0xffab387";
    active_color = "0xff1e1e2e";
    width = 2.0;
  };

  security.pam.services.sudo_local = {
    enable = true;
    touchIdAuth = true;
    reattach = true;
  };
}
