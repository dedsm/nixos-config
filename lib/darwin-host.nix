attrs@{
  home-manager,
  lib,
  mkPkgs,
  darwin,
  ...
}:
{
  mkDarwinHost =
    {
      name,
      system,
      user,
      # The host's own modules, normally just ./hosts/<name>.
      modules,
    }:
    let
      pkgs = mkPkgs system;
    in
    darwin.lib.darwinSystem {
      inherit system;

      specialArgs = attrs // {
        inherit user;
      };

      modules = [
        home-manager.darwinModules.home-manager
        {
          nixpkgs.pkgs = pkgs;
          networking.hostName = name;
          users.users.${user}.home = "/Users/${user}";
          system.stateVersion = 6; # Darwin state version

          home-manager.useUserPackages = true;
        }
      ]
      ++ modules
      ++ [
        ../modules/darwin
        ../modules/common
      ];
    };
}
