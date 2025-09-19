# Since I only have one system this is a placeholder for all the configurations I'd use in a laptop
# It should be split into more detailed modules if the situation ever changes (like having a dedicated desktop for instance)
{
  lib,
  pkgs,
  config,
  unfreePkgs,
  unstablePkgs,
  hyprland,
  hc,
  # Add args for the pre-calculated booleans from specialArgs
  anySway,
  anyHyprland,
  ...
}:
with lib; let
  defaultSession =
    if anyHyprland
    then "hyprland-uwsm"
    else "sway";
in {
  config = mkMerge [
    {
      # Use lib.optional for conditional list elements (use args directly)
      system.nixos.tags =
        []
        ++ (lib.optional anySway "sway")
        ++ (lib.optional anyHyprland "hyprland");

      networking.networkmanager = {
        enable = true;
        wifi = {
          backend = "wpa_supplicant";
        };
      };

      fonts.packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-emoji
        liberation_ttf
        fira-code
        fira-code-symbols
        dina-font
        proggyfonts
        unstablePkgs.nerd-fonts.inconsolata-go
      ];

      services.xserver = {
        enable = true;
        displayManager = {
          gdm.enable = true;
          gdm.wayland = true;
        };

        xkb = {
          layout = "us";
          model = "pc105";
          variant = "altgr-intl";
          options = "caps:super";
        };
      };

      # Conditionally set default session (already uses defaultSession variable)
      services.displayManager.defaultSession = defaultSession;

      console.useXkbConfig = true;

      # Enable CUPS to print documents.
      services.printing = {
        enable = true;
        browsing = true;
        startWhenNeeded = true;
        drivers = [unfreePkgs.epson_201207w pkgs.gutenprint];
      };

      services.avahi.enable = true;
      services.avahi.nssmdns4 = true;

      # Open Tablet Driver
      hardware.opentabletdriver = {
        enable = true;
        package = unstablePkgs.opentabletdriver;
      };

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
      services.pulseaudio.enable = false;

      # Enable bluetooth
      hardware.bluetooth = {
        enable = true;
        package = unstablePkgs.bluez;
      };

      services.blueman = {
        enable = true;
      };

      # Enable scanning
      hardware.sane = {
        enable = true;
        extraBackends = [pkgs.sane-airscan];
      };

      security.polkit.enable = true;
      security.rtkit.enable = true;

      security.pam.services.gdm.enableGnomeKeyring = true;
      security.pam.services.gdm.enableKwallet = true;
      security.pam.services.login.enableKwallet = true;
      security.pam.services.hyprlock = {};

      services.accounts-daemon.enable = true;

      environment.etc = {
        "1password/custom_allowed_browsers" = {
          text = ''
            firefox-devedition
          '';
          mode = "0755";
        };
      };

      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };

      services.dbus = {
        enable = true;
        packages = [pkgs.dconf];
      };

      xdg = {
        mime.enable = true;
        icons.enable = true;
        portal = {
          enable = true;
          wlr.enable = true;
          xdgOpenUsePortal = false;
          # gtk portal needed to make gtk apps happy
          extraPortals = [pkgs.xdg-desktop-portal-gtk];
        };
      };

      programs.light = {enable = true;};
    }

    # Conditionally enable Sway system programs (use args directly)
    (mkIf anySway {
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
    })

    # Conditionally enable Hyprland system programs (use args directly)
    (mkIf anyHyprland {
      programs.hyprland = {
        enable = true;
        withUWSM = true;
        # You might want to conditionally enable the hyprland portal too
        # xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-hyprland ]; # Or use hyprland flake's portalPackage
      };
      # Maybe add hyprland package to systemPackages if needed globally?
      # environment.systemPackages = [ hyprland.packages.${pkgs.system}.hyprland ];
    })

    {
      # Enable touchpad support (enabled default in most desktopManager).
      # services.xserver.libinput.enable = true;

      virtualisation.docker = {
        enable = true;
        package = unstablePkgs.docker;
        liveRestore = false;
        enableOnBoot = false; # Don't start Docker on boot - start on-demand via socket activation
      };

      # virtualisation.virtualbox.host.enable = true;
      # virtualisation.virtualbox.host.enableExtensionPack = true;

      virtualisation.libvirtd.enable = true;
      virtualisation.spiceUSBRedirection.enable = true;
      programs.dconf.enable = true;

      nixpkgs.config.allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) ["Oracle_VM_VirtualBox_Extension_Pack"];

      # System users are now handled directly in lib/host.nix via config.system.users

      home-manager.useGlobalPkgs = false;
      home-manager.useUserPackages = true;

      # List packages installed in system profile. To search, run:
      # $ nix search wget
      environment.systemPackages = with pkgs; [
        git
        any-nix-shell
        nixfmt-rfc-style
        qt5.qtwayland
        plasma5Packages.kwallet
        kdePackages.kwallet-pam
        ripgrep
        virtiofsd # Shared files with virt-manager
        lm_sensors
      ];
      environment.enableAllTerminfo = true;

      # Some programs need SUID wrappers, can be configured further or are
      # started in user sessions.
      # programs.mtr.enable = true;

      programs._1password = {
        enable = true;
        package = unfreePkgs._1password-cli;
      };
      programs._1password-gui = {
        enable = true;
        polkitPolicyOwners = ["david"];
        package = unfreePkgs._1password-gui;
      };

      programs.ssh = {startAgent = false;};
      programs.gnupg.agent = {
        enable = true;
        enableSSHSupport = true;
        pinentryPackage = pkgs.pinentry-gnome3;
      };

      # List services that you want to enable:

      services.pcscd.enable = true;
      services.hardware.bolt.enable = true;

      services.fwupd = {
        enable = true;
        extraRemotes = ["lvfs-testing"];
      };
      environment.etc."fwupd/uefi_capsule.conf".text = lib.mkForce ''
        [uefi_capsule]
        OverrideESPMountPoint=${config.boot.loader.efi.efiSysMountPoint}
        DisableCapsuleUpdateOnDisk=true
      '';

      services.fprintd = {enable = true;};
      services.udev = {packages = with pkgs; [yubikey-personalization];};

      services.ddclient = {
        enable = true;
        configFile = "/etc/nixos/ddclient.conf";
      };
    }
  ];
}
