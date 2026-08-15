{
  description = "David's NixOS configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    unstable.url = "nixpkgs/nixos-unstable";
    hyprland.url = "git+https://github.com/dedsm/Hyprland?submodules=1&ref=stable_branch";
    #hyprland.url = "git+https://github.com/dedsm/Hyprland?submodules=1&rev=0ac0f32671b949b7bde276f1175bed035fb09fd9";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware = {url = "github:NixOS/nixos-hardware";};

    hyprdynamicmonitors = {
      url = "github:fiffeek/hyprdynamicmonitors";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = attrs @ {
    nixpkgs,
    unstable,
    hyprland,
    home-manager,
    nixos-hardware,
    hyprdynamicmonitors,
    darwin,
    ...
  }: let
    lib = nixpkgs.lib;

    mkPkgs = system: let
      unstablePkgs = import unstable {
        localSystem = system;
        config = {
          allowUnfree = true;
        };
      };
      unfreePkgs = import nixpkgs {
        localSystem = system;
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
        localSystem = system;
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
        hyprdynamicmonitors
        darwin
        ;
    };

    inherit (util) nixosHost darwinHost;

    # The systems the hosts below are built for. Only used to decide which
    # `packages` outputs to expose.
    supportedSystems = ["x86_64-linux" "aarch64-darwin"];

    defaultUser = {
      name = "david";
      groups = [
        "disk"
        "wheel"
        "video"
        "docker"
        "networkmanager"
        "lp"
        "scanner"
        "uinput" # solaar
      ];
    };

    inherit (util) host;

    # Define reusable common user settings
    davidShared = pkgs: {
      tmux.enable = true;
      herdr.enable = true;
      nvim.enable = true;
      zsh.enable = true;
      starship.enable = true;
      claude-code.enable = true;
      playwright.enable = true;
      antigravity.enable = true;

      # Defaults for modules not enabled on all platforms
      kdeconnect.enable = false;
      lorri.enable = false;
      swaync.enable = false;
      network-manager.enable = false;
      bluetooth.enable = false;
      wayland.enable = false;
      hyprland.enable = false;
      theme.enable = true;
      defaults.enable = false;
      direnv.enable = true;
      fzf.enable = true;
      zoxide.enable = true;
      ssh.enable = true;
      ghostty.enable = false;
      gh.enable = true;

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
          tag.gpgsign = true;
          push = {default = "simple";};
          diff = {tool = "vimdiff";};
          pull = {ff = "only";};
          init = {defaultBranch = "master";};
          worktree = {guessRemote = true;};
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
          # Pinned to stable: unstable's 570.0.0 bundles python 3.14 and fails
          # auto-patchelf (missing libtcl9/libpython3.14). Revert to unstable
          # once nixpkgs fixes the bundled-python patchelf breakage.
          (google-cloud-sdk.withExtraComponents (with google-cloud-sdk.components; [
            gke-gcloud-auth-plugin
          ]))
          docker-credential-gcr
          amazon-ecr-credential-helper
          jq
          yq
          fzf
          krew
          prettier

          # Personal task tracker (git-backed); used by the `brain` Claude skill.
          # `dstask-note` wraps `dstask note` in a pty — the bare command
          # silently no-ops without a TTY (see pkgs/dstask-note/default.nix).
          dstask
          pkgs.local.dstask-note

          # K8S
          k9s

          # On PATH by name for herdr's agent integration: the hook it installs
          # into Claude Code is `sh` + a `python3` heredoc (herdr itself is
          # Rust), and it exits 0 without reporting when `command -v python3`
          # fails — which silently costs agent session recovery. See
          # "Restart behaviour" in docs/herdr.md. Same store path `brain`
          # already pins via patchShebangs, so this costs no extra build.
          python3

          # rtk (Rust Token Killer) — token-optimizing CLI proxy.
          # Pinned to stable: unstable's 0.43.0 fails its test build under
          # `-D warnings` on upstream dead code (FILTERS_TOML,
          # TomlFilterRegistry::load). Revert to `pkgs.unstable.rtk` once
          # unstable ships a version that compiles cleanly.
          rtk
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
            slurp
            grim
            marksman
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
            any-nix-shell
            watch
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
      performance.enable = true;
      gnome-programs.enable = true;
      gnome-services.enable = true;
      hyprland.enable = true;
      greetd = {
        enable = true;
        autologinUser = "david";
      };
      bluetooth.enable = true;
      printing.enable = true;
      scanning.enable = true;
      virtualisation.enable = true;
      onepassword.enable = true;
      gnupg.enable = true;
      peripherals.enable = true;
      fwupd.enable = true;
      ddclient.enable = true;

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
          hyprland.enable = true;
          anyrun.enable = true;
          packages = pkgs:
            (davidNixos pkgs).packages pkgs
            ++ (with pkgs; [
              pkgs.local.slack
              pkgs.unstable.spotify
              (pkgs.unstable.vscode.override {
                commandLineArgs = "--password-store=gnome-libsecret";
              })
              # Cursor.ai
              pkgs.unstable.synology-drive-client
              pkgs.unstable.ledger-live-desktop
              pkgs.unstable.avizo
              pkgs.unstable.awscli2
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
        hardwareModules = [
          nixos-hardware.nixosModules.framework-amd-ai-300-series
          ./hosts/manwe/hardware-configuration.nix
        ];
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

    # The `pkgs/` overlay, exposed so `nix build .#<name>` works and so
    # `nix-update --flake <name>` (see scripts/update-packages.sh) has an
    # attribute path to resolve. Packages that cannot evaluate for a system —
    # cursor-appimage on Darwin, say — are dropped rather than breaking
    # `nix flake show` for everything else.
    packages = lib.genAttrs supportedSystems (
      system: let
        pkgs = mkPkgs system;
        evaluates = p: (builtins.tryEval (p.drvPath or null)).success;
      in
        lib.filterAttrs (_: p: lib.isDerivation p && evaluates p) pkgs.local
    );

    # `nix fmt` formats the repo. nixfmt is the formatter RFC 166 selected as
    # the Nix standard, which is why `pkgs.nixfmt` is now the RFC style and the
    # older one is `nixfmt-classic`. Declaring it here makes the choice
    # machine-checkable (`nix fmt -- --check .`) instead of a claim in a doc —
    # the repo was formatted with alejandra for a long time while CLAUDE.md
    # said nixfmt. The `core` and `nvim` modules put the same package on PATH.
    formatter = lib.genAttrs supportedSystems (system: (mkPkgs system).nixfmt);
  };
}
