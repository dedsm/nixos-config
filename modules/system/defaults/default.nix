# Since I only have one system this is a placeholder for all the configurations I'd use in a laptop
# It should be split into more detailed modules if the situation ever changes (like having a dedicated desktop for instance)
{ lib, pkgs, config, unfreePkgs, unstablePkgs, ... }:
with lib;
let
  cfg = config.dedsm.defaults;
  userOpts = _: {
    options = {
      name = mkOption { type = types.str; };
      groups = mkOption { type = with types; listOf str; };
    };
  };
  mkUser = k: v: {
    isNormalUser = true;
    name = v.name;
    extraGroups = v.groups;
  };
in {
  options.dedsm.defaults = with types; {
    users = mkOption { type = types.attrsOf (submodule userOpts); };
  };

  config = {

    networking.networkmanager.enable = true;

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk
      noto-fonts-emoji
      liberation_ttf
      fira-code
      fira-code-symbols
      dina-font
      proggyfonts
      nerdfonts
    ];

    services.xserver = {
      enable = true;
      displayManager = {
        gdm.enable = true;
        gdm.wayland = true;
        defaultSession = "hyprland";
      };

      layout = "us";
      xkbModel = "pc105";
      xkbVariant = "altgr-intl";
      xkbOptions = "caps:super";
    };

    console.useXkbConfig = true;

    # Enable CUPS to print documents.
    services.printing = {
      enable = true;
      browsing = true;
      startWhenNeeded = true;
      drivers = [ unfreePkgs.epson_201207w pkgs.gutenprint ];
    };

    services.avahi.enable = true;
    services.avahi.nssmdns = true;

    # Ledger support
    hardware.ledger.enable = true;

    # Logitech control
    hardware.logitech = {
      wireless = {
        enable = true;
        enableGraphical = true;
      };
    };
    # solaar needs users to be able to write to uinput
    hardware.uinput.enable = true;

    # Enable sound.
    sound.enable = true;
    hardware.pulseaudio.enable = false;

    # Enable bluetooth
    hardware.bluetooth.enable = true;
    services.blueman.enable = true;

    # Enable scanning
    hardware.sane = {
      enable = true;
      extraBackends = [ pkgs.sane-airscan ];
    };

    security.polkit.enable = true;
    security.rtkit.enable = true;

    security.pam.services.gdm.enableGnomeKeyring = true;
    security.pam.services.gdm.enableKwallet = true;
    security.pam.services.login.enableKwallet = true;

    services.accounts-daemon.enable = true;

    environment.etc = {
      "wireplumber/policy.lua.d/51-bluez-config.lua".text = ''

        bluetooth_policy.policy = {
          -- Whether to store state on the filesystem.
          ["use-persistent-storage"] = true,

          -- Whether to use headset profile in the presence of an input stream.
          ["media-role.use-headset-profile"] = true,

          -- Application names correspond to application.name in stream properties.
          -- Applications which do not set media.role but which should be considered
          -- for role based profile switching can be specified here.
          ["media-role.applications"] = { "Firefox Developer Edition",
            "Firefox",
            "Chromium input",
            "Google Chrome input",
            "Brave input",
            "Microsoft Edge input",
            "Vivaldi input",
            "ZOOM VoiceEngine",
            "Telegram Desktop",
            "telegram-desktop",
            "linphone",
            "Mumble" 
          },
        }
      '';
    };

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    services.dbus = {
      enable = true;
      packages = [ pkgs.dconf ];
    };

    xdg = {
      mime.enable = true;
      icons.enable = true;
      portal = {
        enable = true;
        wlr.enable = false;
        # gtk portal needed to make gtk apps happy
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        gtkUsePortal = false;
      };
    };

    programs.light = { enable = true; };
    programs.hyprland.enable = true;

    programs.sway = {
      enable = true;
      wrapperFeatures = {
        gtk = true;
        base = true;
      };
      extraSessionCommands = ''
        export SDL_VIDEODRIVER=wayland
        export QT_WAYLAND_DISABLE_WINDOWDECORATION="1"
        export _JAVA_AWT_WM_NONREPARENTING=1
        export MOZ_ENABLE_WAYLAND=1
        export NIXOS_OZONE_WL=1
      '';
    };

    # Enable touchpad support (enabled default in most desktopManager).
    # services.xserver.libinput.enable = true;

    virtualisation.docker = {
      enable = true;
      package = unstablePkgs.docker_24;
    };

    # virtualisation.virtualbox.host.enable = true;
    # virtualisation.virtualbox.host.enableExtensionPack = true;

    virtualisation.libvirtd.enable = true;
    virtualisation.spiceUSBRedirection.enable = true;
    programs.dconf.enable = true;

    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [ "Oracle_VM_VirtualBox_Extension_Pack" ];

    # Define a user account. Don't forget to set a password with ‘passwd’.
    users.users = mapAttrs mkUser cfg.users;

    home-manager.useGlobalPkgs = false;
    home-manager.useUserPackages = true;

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    environment.systemPackages = with pkgs; [
      git
      any-nix-shell
      rnix-lsp
      nixfmt
      qt5.qtwayland
      plasma5Packages.kwallet
      ripgrep
      virtiofsd # Shared files with virt-manager
    ];
    environment.enableAllTerminfo = true;

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    # programs.mtr.enable = true;

    programs._1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "david" ];
      package = unfreePkgs._1password-gui;
    };

    programs.ssh = { startAgent = false; };
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryFlavor = "gnome3";
    };

    # List services that you want to enable:

    services.pcscd.enable = true;
    services.hardware.bolt.enable = true;

    services.fwupd = {
      enable = true;
      extraRemotes = [ "lvfs-testing" ];
    };
    environment.etc."fwupd/uefi_capsule.conf".text = lib.mkForce ''
      [uefi_capsule]
      OverrideESPMountPoint=${config.boot.loader.efi.efiSysMountPoint}
      DisableCapsuleUpdateOnDisk=true
    '';

    services.fprintd = { enable = true; };
    services.udev = { packages = with pkgs; [ yubikey-personalization ]; };

    services.ddclient = {
      enable = false;
      protocol = "namecheap";
      username = "dedsm.com";
      passwordFile = "/etc/nixos/ddclientPassword";
      domains = [ "mobile.dedsm.com" ];
    };
  };
}
