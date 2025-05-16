{
  description = "David's NixOS configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    unstable.url = "nixpkgs/nixos-unstable";
    hyprland.url = "git+https://github.com/dedsm/Hyprland?submodules=1&ref=stable_branch";
    #hyprland.url = "git+https://github.com/dedsm/Hyprland?submodules=1&rev=0ac0f32671b949b7bde276f1175bed035fb09fd9";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fw-fanctrl = {
      url = "github:TamtamHero/fw-fanctrl/packaging/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = {url = "github:NixOS/nixos-hardware";};
  };

  outputs = attrs @ {
    nixpkgs,
    unstable,
    hyprland,
    home-manager,
    nixos-hardware,
    fw-fanctrl,
    ...
  }: let
    lib = nixpkgs.lib;
    system = "x86_64-linux";
    unstablePkgs = import unstable {
      inherit system;
      config = {allowUnfree = true;};
    };
    unfreePkgs = import nixpkgs {
      inherit system;
      config = {allowUnfree = true;};
    };
    localpkgs = import ./pkgs {hyprlandPkgs = hyprland;};
    overlaidPkgs = import nixpkgs {
      inherit system;
      overlays = [localpkgs];
    };
    util = import ./lib {
      inherit
        system
        nixpkgs
        unstable
        overlaidPkgs
        unstablePkgs
        unfreePkgs
        home-manager
        nixos-hardware
        lib
        hyprland
        fw-fanctrl
        ;
    };

    defaultUser = {
      name = "david";
      groups = [
        "disk"
        "wheel"
        "video"
        "docker"
        "networkmanager"
        "vboxusers"
        "lp"
        "scanner"
        "libvirtd"
        "uinput" # solaar
      ];
    };

    inherit (util) host;

    # Define reusable common user settings
    davidCommon = {
      tmux.enable = true;
      nvim.enable = true;
      zsh.enable = true;
      kdeconnect.enable = true;
      lorri.enable = true;
      mako.enable = true;
      network-manager.enable = true;
      bluetooth.enable = true;
      # Sway/Hyprland enablement will be per-host user config
      starship.enable = true;
      wayland.enable = true;
      defaults.enable = true;
      git = {
        enable = true;
        lfs = {
          enable = true;
          skipSmudge = true;
        };
        userEmail = "davidesousa@gmail.com";
        userName = "David De Sousa";

        ignores = [
          ".envrc"
          ".python-version"
          ".mypy_cache"
          ".direnv"
          ".tool-versions"
          "shell.nix"
        ];

        signing = {
          key = "8655217C8614EB611CF2259DF287187DBA42E303";
          signByDefault = true;
        };

        extraConfig = {
          push = {default = "simple";};
          diff = {tool = "vimdiff";};
          pull = {ff = "only";};
          init = {defaultBranch = "master";};
        };

        includes = [
          {
            path = "~/Develop/DealMaker/.gitconfig";
            condition = "gitdir:~/Develop/DealMaker/";
          }
        ];
      };

      stateVersion = "22.05"; # Default state version

      # Common packages can go here, host-specific ones below
      packages = with overlaidPkgs; [
        gnome-themes-extra
        adwaita-icon-theme
        gnome-icon-theme
        gnome-calculator
        nautilus
        eog
        evince
        polkit_gnome
        docker-credential-helpers
        (pkgs.writers.writePython3Bin "i3xmonadhelper" {
          libraries = [pkgs.python3Packages.i3ipc];
        } (builtins.readFile ./custom/david/i3xmonadhelper.py))
        wl-clipboard
        moonlight-qt
        clipman
        playerctl
        httpie
        gimp
        scrot
        grobi
        chromium
        libreoffice
        ffmpeg
        kubectl
        stern
        p7zip
        unfreePkgs.dropbox
        vlc
        ntfs3g
        kubernetes-helm
        sops
        docker-credential-gcr
        amazon-ecr-credential-helper
        jq
        yq
        digikam
        exiftool
        wireshark
        krew
        pavucontrol
        pamixer
        xsane
        imagemagick
        networkmanagerapplet
        bemenu
        slurp
        grim
        marksman
        nodePackages.prettier
        pandoc
        virt-manager
        # Remarkable Stream
        unstablePkgs.restream
        # 1password CLI
        unstablePkgs._1password-cli
        # Snyk
        snyk
      ];
    };

    rootCommon = {
      tmux.enable = true;
      nvim.enable = true;
      zsh.enable = true;
      kdeconnect.enable = false;
      lorri.enable = false;
      mako.enable = false;
      network-manager.enable = false;
      bluetooth.enable = false;
      sway.enable = false;
      hyprland.enable = false;
      wayland.enable = false;
      git.enable = false;
      starship.enable = true;
      defaults.enable = false;
      packages = [];
      stateVersion = "22.05";
    };


    # Define the unified configuration for the 'manwe' host
    manweConfig = {
      # Renamed from 'system' to avoid confusion with config.system
      systemAttrs = { # Corresponds to the old systemConfig flags
        laptop.enable = true;
        gnome-programs.enable = true; # Keep this? Or derive from user needs?
        gnome-services.enable = true; # Keep this? Or derive from user needs?
        fw-fanctrl.enable = false;
        # We don't need sway/hyprland flags here anymore if defaults derive them
        # System users definition moved out
      };

      # Define system users separately
      systemUsers = {
        david = {
          isNormalUser = true;
          extraGroups = defaultUser.groups;
        };
        # root = { ... };
      };

      # Renamed from 'users' for clarity
      homeManagerUsers = { # Home Manager configs specific to 'manwe'
        david = davidCommon // {
          # Host-specific overrides/additions for david on manwe
          sway.enable = true;
          hyprland.enable = false; # Explicitly false or omit if default is false
          # Host-specific packages for david on manwe
          packages = davidCommon.packages ++ (with overlaidPkgs; [
            swaylock
            unstablePkgs.slack
            unstablePkgs.spotify
            (unstablePkgs.google-cloud-sdk.withExtraComponents [
              unstablePkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
            ])
            unstablePkgs.vscode
            # Cursor.ai
            unstablePkgs.code-cursor
            unstablePkgs.synology-drive-client
            unstablePkgs.ledger-live-desktop
            unstablePkgs.avizo
            awscli2
          ]);
        };
        root = rootCommon;
      };
      stateVersion = "21.05"; # System state version
    };

  in {
    nixosConfigurations = {
      manwe = host.mkHost {
        name = "manwe";
        # Pass the unified config instead of separate ones
        config = manweConfig;
      };
      # Example for a future host:
      # tower = host.mkHost {
      #   name = "tower";
      #   config = {
      #     system = { laptop.enable = false; /* ... */ };
      #     users = {
      #       david = davidCommon // { hyprland.enable = true; /* ... */ };
      #       anotherUser = { /* ... */ };
      #     };
      #     stateVersion = "24.05";
      #   };
      # };
    };
  };
}
