{
  description = "David's NixOS configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
    unstable.url = "nixpkgs/nixos-unstable";
    hyprland.url = "git+https://github.com/dedsm/Hyprland?submodules=1&ref=stable_branch";
    #hyprland.url = "git+https://github.com/dedsm/Hyprland?submodules=1&rev=0ac0f32671b949b7bde276f1175bed035fb09fd9";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fw-fanctrl = {
      url = "github:TamtamHero/fw-fanctrl/packaging/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = {url = "github:NixOS/nixos-hardware";};

    hyprdynamicmonitors = {
      url = "github:fiffeek/hyprdynamicmonitors";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = attrs @ {
    nixpkgs,
    unstable,
    hyprland,
    home-manager,
    nixos-hardware,
    fw-fanctrl,
    hyprdynamicmonitors,
    darwin,
    ...
  }: let
    lib = nixpkgs.lib;

    mkPkgs = system: let
      unstablePkgs = import unstable {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
      unfreePkgs = import nixpkgs {
        inherit system;
        config = {allowUnfree = true;};
      };
      localpkgs = import ./pkgs {
        hyprlandPkgs = hyprland;
        unstablePkgs = unstablePkgs;
      };
      overlay = final: prev: {
        unstable = unstablePkgs;
        unfree = unfreePkgs;
        local = localpkgs final prev;
      };
    in
      import nixpkgs {
        inherit system;
        overlays = [overlay];
      };
    util = import ./lib {
      inherit
        nixpkgs
        unstable
        mkPkgs
        home-manager
        nixos-hardware
        lib
        hyprland
        fw-fanctrl
        hyprdynamicmonitors
        darwin
        ;
    };

    inherit (util) nixosHost darwinHost;

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
    davidShared = pkgs: {
      tmux.enable = true;
      nvim.enable = true;
      zsh.enable = true;
      starship.enable = true;
      claude-code.enable = true;
      gemini-cli.enable = true;

      # Defaults for modules not enabled on all platforms
      kdeconnect.enable = false;
      lorri.enable = false;
      swaync.enable = false;
      network-manager.enable = false;
      bluetooth.enable = false;
      wayland.enable = false;
      sway.enable = false;
      hyprland.enable = false;
      theme.enable = true;
      defaults.enable = false;
      direnv.enable = true;
      fzf.enable = true;
      zoxide.enable = true;
      ssh.enable = true;
      ghostty.enable = false;

      git = {
        enable = true;
        lfs = {
          enable = true;
          skipSmudge = true;
        };
        ignores = [
          ".envrc"
          ".python-version"
          ".mypy_cache"
          ".direnv"
          ".tool-versions"
          "shell.nix"
        ];
        settings = {
          user = {
            email = "davidesousa@gmail.com";
            name = "David De Sousa";
            signingkey = "8655217C8614EB611CF2259DF287187DBA42E303";
          };
          commit.gpgsign = true;
          push = {default = "simple";};
          diff = {tool = "vimdiff";};
          pull = {ff = "only";};
          init = {defaultBranch = "master";};
        };
      };

      stateVersion = "22.05"; # Default state version

      # Common packages
      packages = pkgs:
        with pkgs; [
          gnumake
          docker-credential-helpers
          httpie
          kubectl
          stern
          p7zip
          sops
          (pkgs.unstable.google-cloud-sdk.withExtraComponents( with pkgs.unstable.google-cloud-sdk.components; [
              gke-gcloud-auth-plugin
            ]))
          docker-credential-gcr
          amazon-ecr-credential-helper
          jq
          yq
          fzf
          krew
          nodePackages.prettier

          # Github CLI
          gh
        ];
    };

    davidNixos = pkgs:
      (davidShared pkgs)
      // {
        kdeconnect.enable = true;
        lorri.enable = true;
        swaync.enable = true;
        network-manager.enable = true;
        bluetooth.enable = true;
        wayland.enable = true;
        defaults.enable = true;

        # zsh.initContent = ''
        #   if [ $EUID -ne 0 ]; then
        #     export PATH="$PATH:$HOME/.krew/bin"
        # '';

        packages = pkgs:
          ((davidShared pkgs).packages pkgs)
          ++ (with pkgs; [
            gnome-themes-extra
            adwaita-icon-theme
            gnome-icon-theme
            gnome-calculator
            nautilus
            eog
            evince
            polkit_gnome
            (pkgs.writers.writePython3Bin "i3xmonadhelper" {
              libraries = [pkgs.python3Packages.i3ipc];
            } (builtins.readFile ./custom/david/i3xmonadhelper.py))
            wl-clipboard
            moonlight-qt
            clipman
            playerctl
            gimp
            scrot
            grobi
            chromium
            libreoffice
            ffmpeg
            pkgs.unfree.dropbox
            vlc
            ntfs3g
            kubernetes-helm
            digikam
            exiftool
            wireshark
            pavucontrol
            pamixer
            xsane
            imagemagick
            networkmanagerapplet
            bemenu
            slurp
            grim
            marksman
            virt-manager
            pkgs.unstable.restream
            pkgs.unfree._1password-cli
          ]);
      };

    davidDarwin = pkgs:
      (davidShared pkgs)
      // {
        # Darwin specific settings
        ghostty.enable = true;
        sketchybar.enable = false;
        stateVersion = "25.11";
        packages = pkgs:
          ((davidShared pkgs).packages pkgs)
          ++ (with pkgs; [
            ripgrep
            gnupg
            pkgs.unstable.antigravity
            any-nix-shell
          ]);
      };

    rootCommon = {
      tmux.enable = true;
      nvim.enable = true;
      zsh.enable = true;
      kdeconnect.enable = false;
      lorri.enable = false;
      swaync.enable = false;
      network-manager.enable = false;
      bluetooth.enable = false;
      sway.enable = false;
      hyprland.enable = false;
      wayland.enable = false;
      theme.enable = false;
      git.enable = false;
      starship.enable = true;
      defaults.enable = false;
      packages = pkgs: [];
      stateVersion = "22.05";
    };

    # Define the unified configuration for the 'manwe' host
    manweSystemConfig = {
      laptop.enable = true;
      gnome-programs.enable = true;
      gnome-services.enable = true;
      fw-fanctrl.enable = false;

      systemUsers = {
        david = {
          isNormalUser = true;
          extraGroups = defaultUser.groups;
        };
      };
      stateVersion = "21.05";
    };
    manweUserConfig = pkgs: {
      david =
        (davidNixos pkgs)
        // {
          sway.enable = false;
          hyprland.enable = true;
          packages = pkgs:
            (davidNixos pkgs).packages pkgs
            ++ (with pkgs; [
              pkgs.local.slack
              pkgs.unstable.spotify
              pkgs.unstable.vscode
              # Cursor.ai
              pkgs.local.cursor-appimage
              pkgs.unstable.antigravity
              pkgs.unstable.synology-drive-client
              pkgs.unstable.ledger-live-desktop
              pkgs.unstable.avizo
              awscli2
            ]);
        };
      root = rootCommon;
    };

    morgothSystemConfig = {
      # Darwin system config if any
      stateVersion = "25.11";
      aerospace.enable = true;
    };

    morgothUserConfig = pkgs: {
      "david.de.sousa" =
        (davidDarwin pkgs)
        // {
          home.homeDirectory = "/Users/david.de.sousa";
          home.stateVersion = "25.11";

          git =
            (davidDarwin pkgs).git
            // {
              includes = [
                {
                  path = "~/Develop/Carv/.gitconfig";
                  condition = "gitdir:~/Develop/Carv/";
                }
              ];
            };

          zsh =
            (davidDarwin pkgs).zsh
            // {
              initContent = ''
                eval "$(/opt/homebrew/bin/brew shellenv)"
                eval "$(docker completion zsh)"
              '';
            };

          packages = pkgs:
            (davidDarwin pkgs).packages pkgs
            ++ (with pkgs; [
            ]);
        };
    };
  in {
    nixosConfigurations = {
      manwe = nixosHost.mkHost {
        name = "manwe";
        system = "x86_64-linux";
        systemConfig = manweSystemConfig;
        userConfigFn = manweUserConfig;
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

    darwinConfigurations = {
      morgoth = darwinHost.mkDarwinHost {
        name = "morgoth";
        system = "aarch64-darwin";
        user = "david.de.sousa";
        systemConfig = morgothSystemConfig;
        userConfigFn = morgothUserConfig;
      };
    };
  };
}
