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
      systemConfig,
      users,
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
          home-manager.users = users;
          users.users.${user}.home = "/Users/${user}";
          system.stateVersion = 6; # Darwin state version

          home-manager.useUserPackages = true;

          dedsm = systemConfig;
        }
        ../modules/darwin
        ../modules/common
      ];
    };
}
