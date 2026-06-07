attrs@{ nixos-hardware, nixpkgs, unstable, home-manager, lib, mkPkgs, hyprland, ... }: {
  mkHost = { name, system, systemConfig, userConfigFn }:
    let
      pkgs = mkPkgs system;
      userConfig = userConfigFn pkgs;
      # Helper to check if any user in the HM config enables a specific module
      anyUserEnables = moduleName:
        builtins.any (userCfg: userCfg.${moduleName}.enable or false) (builtins.attrValues userConfig);

      anySway = anyUserEnables "sway";
      anyHyprland = anyUserEnables "hyprland";

    in
    lib.nixosSystem {
      # inherit system; # System is set via nixpkgs.pkgs

      specialArgs = attrs // {
        hc = userConfig;
        hostSystemConfig = systemConfig;
        # Pass the original values down
        inherit anySway anyHyprland;
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

          # Define assertions using the standard mechanism
          assertions = [
            {
              assertion = anySway != anyHyprland;
              message = "Host \"${name}\" must have exactly one of Sway or Hyprland enabled across its users.";
            }
          ];
        }
        nixos-hardware.nixosModules.framework-amd-ai-300-series
        ../modules/hardware-configuration.nix
        ../modules/common
      ];
    };
}
