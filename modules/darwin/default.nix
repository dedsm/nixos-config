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
      cleanup = "zap";
      autoUpdate = false;
      upgrade = false;
    };
    brews = [
      "cormacrelf/tap/dark-notify"
    ];
    casks = [
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
