{
  description = "David's NixOS configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-23.11";
    unstable.url = "nixpkgs/nixos-unstable";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?rev=e4e84064f2d07810e0c150bce1369a0a00503e9a&submodules=1";
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = { url = "github:NixOS/nixos-hardware"; };
  };

  outputs =
    attrs@{ nixpkgs, unstable, hyprland, home-manager, nixos-hardware, ... }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      unstablePkgs = import unstable {
        inherit system;
        config = { allowUnfree = true; };
      };
      unfreePkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
      localpkgs = import ./pkgs { hyprlandPkgs = hyprland; };
      overlaidPkgs = import nixpkgs {
        inherit system;
        overlays = [ localpkgs ];
      };
      util = import ./lib {
        inherit system nixpkgs unstable overlaidPkgs unstablePkgs unfreePkgs
          home-manager nixos-hardware lib hyprland;
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

      rootHomeManager = {
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

        packages = [ ];

        stateVersion = "22.05";
      };

      defaultHomeManager = {
        tmux.enable = true;
        nvim.enable = true;
        zsh.enable = true;
        kdeconnect.enable = true;
        lorri.enable = true;
        mako.enable = true;
        network-manager.enable = true;
        bluetooth.enable = true;
        sway.enable = true;
        hyprland.enable = false;
        starship.enable = true;
        wayland.enable = true;
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
            push = { default = "simple"; };
            diff = { tool = "vimdiff"; };
            pull = { ff = "only"; };
            init = { defaultBranch = "master"; };
          };

          includes = [{
            path = "~/Develop/DealMaker/.gitconfig";
            condition = "gitdir:~/Develop/DealMaker/";
          }];
        };

        stateVersion = "22.05";

        packages = with overlaidPkgs; [
          unstablePkgs.slack
          unstablePkgs.spotify
          (unstablePkgs.google-cloud-sdk.withExtraComponents ([
            unstablePkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
          ]))
          gnome.gnome-themes-extra
          gnome.adwaita-icon-theme
          gnome-icon-theme
          gnome.gnome-calculator
          gnome.nautilus
          gnome.eog
          evince
          swaylock
          polkit_gnome
          docker-credential-helpers
          (pkgs.writers.writePython3Bin "i3xmonadhelper" {
            libraries = [ pkgs.python3Packages.i3ipc ];
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
          wireshark
          krew
          pavucontrol
          pamixer
          xsane
          imagemagick
          networkmanagerapplet
          bemenu
          waybar
          unstablePkgs.avizo
          awscli2
          slurp
          grim
          unstablePkgs.synology-drive-client
          unstablePkgs.ledger-live-desktop
          marksman
          nodePackages.prettier
          pandoc
          virt-manager
        ];
      };

      homeManagerConfig = {
        "${defaultUser.name}" = defaultHomeManager;
        root = rootHomeManager;
      };

      users = { "${defaultUser.name}" = defaultUser; };

      inherit (util) host;
    in {
      nixosConfigurations = {
        manwe = host.mkHost {
          name = "manwe";
          stateVersion = "21.05";
          systemConfig = {
            laptop.enable = true;
            gnome-programs.enable = true;
            gnome-services.enable = true;
            defaults.users = users;
          };
          homeManagerConfig = homeManagerConfig;
        };
      };
    };
}
