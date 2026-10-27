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
      userConfigFn,
    }:
    let
      pkgs = mkPkgs system;
      userConfig = userConfigFn pkgs;
    in
    darwin.lib.darwinSystem {
      inherit system;

      specialArgs = attrs // {
        hc = userConfig;
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

          dedsm = systemConfig;
        }
        ../modules/darwin
        ../modules/common
      ];
    };
}
