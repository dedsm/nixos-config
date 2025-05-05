attrs@{ system, nixos-hardware, nixpkgs, unstable, home-manager, lib, overlaidPkgs, hyprland, fw-fanctrl, ... }: {
  mkHost = { name, config }:
    lib.nixosSystem {
      inherit system;

      specialArgs = attrs // {
        hc = config.homeManagerUsers or {};
        hostSystemConfig = config.systemAttrs or {};
      };

      modules = [
        (import ../modules/system attrs)
        home-manager.nixosModules.home-manager
        {
          dedsm = config.systemAttrs or {};
          users.users = config.systemUsers or {};
          networking.hostName = name;
          nix.settings = {
            substituters = [ "https://hyprland.cachix.org" ];
            trusted-public-keys = [
              "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
            ];
          };
          nix.registry = {
            nixpkgs.flake = nixpkgs;
            unstable.flake = unstable;
          };
          system.stateVersion = config.stateVersion;
        }
        nixos-hardware.nixosModules.framework-12th-gen-intel
        fw-fanctrl.nixosModules.default
        ../modules/hardware-configuration.nix
        ../modules/home-manager
      ];
    };
}
