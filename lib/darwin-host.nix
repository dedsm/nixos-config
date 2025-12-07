attrs@{ nixpkgs, unstable, home-manager, lib, mkPkgs, darwin, ... }: {
  mkDarwinHost = { name, system, user, systemConfig, userConfigFn }:
    let
      pkgs = mkPkgs system;
      userConfig = userConfigFn pkgs;
    in
    darwin.lib.darwinSystem {
      inherit system;

      specialArgs = attrs // {
        hc = userConfig;
        hostSystemConfig = systemConfig;
        inherit user;
      };

      modules = [
        home-manager.darwinModules.home-manager
        {
          nixpkgs.pkgs = pkgs;
          networking.hostName = name;
          users.users.${user}.home = "/Users/${user}";
          nix.settings = {
          };
          nix.registry = {
            nixpkgs.flake = nixpkgs;
            unstable.flake = unstable;
          };
          system.stateVersion = 6; # Darwin state version

          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;

          dedsm = builtins.removeAttrs systemConfig [ "stateVersion" ];
        }
        ../modules/darwin
        ../modules/common
      ];
    };
}
