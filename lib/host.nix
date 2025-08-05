attrs@{ system, nixos-hardware, nixpkgs, unstable, home-manager, lib, overlaidPkgs, hyprland, fw-fanctrl, ... }: {
  mkHost = { name, config }:
    let
      # Helper to check if any user in the HM config enables a specific module
      anyUserEnables = moduleName: hostConfig:
        builtins.any (userCfg: userCfg.${moduleName}.enable or false) (builtins.attrValues (hostConfig.homeManagerUsers or {}));

      anySway = anyUserEnables "sway" config;
      anyHyprland = anyUserEnables "hyprland" config;

    in
    lib.nixosSystem {
      inherit system;

      specialArgs = attrs // {
        hc = config.homeManagerUsers or {};
        hostSystemConfig = config.systemAttrs or {};
        # Pass the original values down
        inherit anySway anyHyprland;
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

          # Define assertions using the standard mechanism
          assertions = [
            {
              assertion = anySway != anyHyprland;
              message = "Host \"${name}\" must have exactly one of Sway or Hyprland enabled across its users.";
            }
          ];
        }
        nixos-hardware.nixosModules.framework-amd-ai-300-series
        fw-fanctrl.nixosModules.default
        ../modules/hardware-configuration.nix
        ../modules/home-manager
      ];
    };
}
