{
  description = "David's NixOS configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    unstable.url = "nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
    };

    # Google Antigravity (the 2.0 "hub" app, the legacy IDE and the `agy` CLI).
    # nixpkgs has all three (the hub since NixOS/nixpkgs#524225), but they lag
    # this repo, which bumps its pinned tarballs ~3x/week. Taken as a plain source
    # tree rather than a flake: `pkgs/default.nix` calls its package files with
    # our own `unstable` nixpkgs, so its own nixpkgs/flake-utils inputs would
    # only bloat the lock. `nix flake update antigravity-nix` is the updater.
    antigravity-nix = {
      url = "github:jacopone/antigravity-nix";
      flake = false;
    };

    hyprdynamicmonitors = {
      url = "github:fiffeek/hyprdynamicmonitors";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    attrs@{
      nixpkgs,
      unstable,
      home-manager,
      nixos-hardware,
      hyprdynamicmonitors,
      antigravity-nix,
      darwin,
      ...
    }:
    let
      lib = nixpkgs.lib;

      mkPkgs =
        system:
        let
          unstablePkgs = import unstable {
            localSystem = system;
            config = {
              allowUnfree = true;
            };
          };
          unfreePkgs = import nixpkgs {
            localSystem = system;
            config = {
              allowUnfree = true;
            };
          };
          localpkgs = import ./pkgs {
            unstablePkgs = unstablePkgs;
            antigravityNix = antigravity-nix;
          };
          overlay = final: prev: {
            unstable = unstablePkgs;
            unfree = unfreePkgs;
            local = localpkgs final prev;
          };
        in
        import nixpkgs {
          localSystem = system;
          overlays = [ overlay ];
        };
      util = import ./lib {
        inherit
          nixpkgs
          unstable
          mkPkgs
          home-manager
          nixos-hardware
          lib
          hyprdynamicmonitors
          darwin
          ;
      };

      inherit (util) nixosHost darwinHost;

      # The systems the hosts below are built for. Only used to decide which
      # `packages` outputs to expose.
      supportedSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

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

      # Define the unified configuration for the 'manwe' host
      manweSystemConfig = {
        laptop.enable = true;
        performance.enable = true;
        gnome-programs.enable = true;
        gnome-services.enable = true;
        hyprland.enable = true;
        greetd.enable = true;
        bluetooth.enable = true;
        printing.enable = true;
        scanning.enable = true;
        virtualisation.enable = true;
        onepassword.enable = true;
        gnupg.enable = true;
        peripherals.enable = true;
        fingerprintPolicy = {
          enable = true;
          # Using dedsm.fingerprintPolicy's defaults. Fingerprint is refused,
          # and the password required, after a restart or logout, after 5
          # failed matches, after 48h with no unlock, or when the password is
          # over 156h old and there has been no fingerprint unlock for 4h.
          # See docs/login-flow.md.
          # The lock screen authenticates as david, not root, so its password
          # unlock can only refresh the clock if david may write the state.
          users = [ "david" ];
        };
        fwupd.enable = true;
        ddclient.enable = true;
        dms.enable = true;

        systemUsers = {
          david = {
            isNormalUser = true;
            extraGroups = defaultUser.groups;
          };
        };
        stateVersion = "21.05";
      };

      # Each user is a Home Manager module: a layer from users/ plus whatever
      # is specific to this host.
      manweUsers = {
        david =
          { pkgs, ... }:
          {
            imports = [ ./users/david/nixos.nix ];
            dedsm.hyprland.enable = true;
            home.packages = [
              pkgs.local.slack
              pkgs.local.granola
              pkgs.unstable.spotify
              (pkgs.unstable.vscode.override {
                commandLineArgs = "--password-store=gnome-libsecret";
              })
              pkgs.unstable.synology-drive-client
              pkgs.unstable.ledger-live-desktop
              pkgs.unstable.awscli2
            ];
          };
        root = ./users/root.nix;
      };

      morgothSystemConfig = {
        aerospace.enable = true;
      };

      morgothUsers = {
        "david.de.sousa" = {
          imports = [ ./users/david/darwin.nix ];
          programs.git.includes = [
            {
              path = "~/Develop/Carv/.gitconfig";
              condition = "gitdir:~/Develop/Carv/";
            }
          ];
          dedsm.zsh.extraInit = ''
            eval "$(/opt/homebrew/bin/brew shellenv)"
            eval "$(docker completion zsh)"
          '';
        };
      };
    in
    {
      nixosConfigurations = {
        manwe = nixosHost.mkHost {
          name = "manwe";
          system = "x86_64-linux";
          systemConfig = manweSystemConfig;
          users = manweUsers;
          hardwareModules = [
            nixos-hardware.nixosModules.framework-amd-ai-300-series
            ./hosts/manwe/hardware-configuration.nix
          ];
        };
      };

      darwinConfigurations = {
        morgoth = darwinHost.mkDarwinHost {
          name = "morgoth";
          system = "aarch64-darwin";
          user = "david.de.sousa";
          systemConfig = morgothSystemConfig;
          users = morgothUsers;
        };
      };

      # The `pkgs/` overlay, exposed so `nix build .#<name>` works and so
      # `nix-update --flake <name>` (see scripts/update-packages.sh) has an
      # attribute path to resolve. Packages that cannot evaluate for a system —
      # cli-notify on Linux, say — are dropped rather than breaking
      # `nix flake show` for everything else.
      packages = lib.genAttrs supportedSystems (
        system:
        let
          pkgs = mkPkgs system;
          evaluates = p: (builtins.tryEval (p.drvPath or null)).success;
        in
        lib.filterAttrs (_: p: lib.isDerivation p && evaluates p) pkgs.local
      );

      # `nix fmt` formats the repo. nixfmt is the formatter RFC 166 selected as
      # the Nix standard, which is why `pkgs.nixfmt` is now the RFC style and the
      # older one is `nixfmt-classic`. Declaring it here makes the choice
      # machine-checkable (`nix fmt -- --ci`) instead of a claim in a doc — the
      # repo was formatted with alejandra for a long time while CLAUDE.md said
      # nixfmt. The `core` and `nvim` modules put the same package on PATH.
      #
      # `nixfmt-tree` is nixfmt behind treefmt: bare `nix fmt` walks the tree
      # itself, where a plain `pkgs.nixfmt` formatter gets no argument from `nix
      # fmt` and reads stdin instead, dying with "unexpected end of input". Nix
      # deprecated passing a path (`nix fmt .`) to work around that, and names
      # this wrapper as the replacement.
      formatter = lib.genAttrs supportedSystems (system: (mkPkgs system).nixfmt-tree);
    };
}
