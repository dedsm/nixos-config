attrs@{ nixpkgs, unstable, home-manager, lib, mkPkgs, hyprland, ... }: {
  mkHost = { name, system, systemConfig, userConfigFn, hardwareModules ? [] }:
    let
      pkgs = mkPkgs system;
      userConfig = userConfigFn pkgs;
    in
    lib.nixosSystem {
      # inherit system; # System is set via nixpkgs.pkgs

      specialArgs = attrs // {
        hc = userConfig;
        hostSystemConfig = systemConfig;
      };

      modules = [
        (import ../modules/nixos attrs)
        home-manager.nixosModules.home-manager
        ({ modulesPath, ... }: {
          imports = [ (modulesPath + "/misc/nixpkgs/read-only.nix") ];
          nixpkgs.pkgs = pkgs;
        })
        {
          dedsm = builtins.removeAttrs systemConfig [ "stateVersion" "systemUsers" ];
          users.users = systemConfig.systemUsers or {};
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
          system.stateVersion = systemConfig.stateVersion;
        }
      ]
      ++ hardwareModules
      ++ [
        ../modules/common
      ];
    };
}
