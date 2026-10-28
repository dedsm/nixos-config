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
      darwin,
      ...
    }:
    let
      lib = nixpkgs.lib;

      mkPkgs = import ./lib/pkgs.nix { inherit nixpkgs unstable; };

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
    in
    {
      nixosConfigurations = {
        manwe = nixosHost.mkHost {
          name = "manwe";
          system = "x86_64-linux";
          modules = [ ./hosts/manwe ];
        };
      };

      darwinConfigurations = {
        morgoth = darwinHost.mkDarwinHost {
          name = "morgoth";
          system = "aarch64-darwin";
          user = "david.de.sousa";
          modules = [ ./hosts/morgoth ];
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
