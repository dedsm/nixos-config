attrs@{ system, home-manager, lib, overlaidPkgs, ... }: {
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
          system.stateVersion = stateVersion;
        }
        ../modules/hardware-configuration.nix
        ../modules/home-manager
      ];
    };
}
