attrs@{ system, nixos-hardware, home-manager, lib, overlaidPkgs, hyprland, ... }: {
  mkHost = { name, systemConfig ? { }, stateVersion, homeManagerConfig ? { } }:
    lib.nixosSystem {
      inherit system;

      specialArgs = attrs // { hc = homeManagerConfig; };

      modules = [
        (import ../modules/system attrs)
        home-manager.nixosModules.home-manager
        {
          dedsm = systemConfig;
          networking.hostName = name;
          nix.settings = {
            substituters = [ "https://hyprland.cachix.org" ];
            trusted-public-keys = [
              "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
            ];
          };
          system.stateVersion = stateVersion;
        }
        nixos-hardware.nixosModules.common-gpu-intel
        nixos-hardware.nixosModules.framework-12th-gen-intel
        ../modules/hardware-configuration.nix
        ../modules/home-manager
      ];
    };
}
