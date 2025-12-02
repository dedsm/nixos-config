attrs@{ system, nixpkgs, unstable, home-manager, lib, overlaidPkgs, darwin, ... }: {
  mkDarwinHost = { name, config }:
    darwin.lib.darwinSystem {
      inherit system;
      
      specialArgs = attrs // {
        hc = config.homeManagerUsers or {};
        hostSystemConfig = config.systemAttrs or {};
      };

      modules = [
        home-manager.darwinModules.home-manager
        {
          networking.hostName = name;
          services.nix-daemon.enable = true;
          nix.settings = {
          };
          nix.registry = {
            nixpkgs.flake = nixpkgs;
            unstable.flake = unstable;
          };
          system.stateVersion = 4; # Darwin state version
          
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users = config.homeManagerUsers or {};
        }
        ../modules/darwin
      ];
    };
}
