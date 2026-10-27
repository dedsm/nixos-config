attrs@{
  home-manager,
  lib,
  mkPkgs,
  ...
}:
{
  mkHost =
    {
      name,
      system,
      systemConfig,
      users,
      hardwareModules ? [ ],
    }:
    let
      pkgs = mkPkgs system;
    in
    lib.nixosSystem {
      specialArgs = attrs;

      modules = [
        ../modules/nixos
        home-manager.nixosModules.home-manager
        ({ modulesPath, ... }: {
          imports = [ (modulesPath + "/misc/nixpkgs/read-only.nix") ];
          nixpkgs.pkgs = pkgs;
        })
        {
          dedsm = builtins.removeAttrs systemConfig [
            "stateVersion"
            "systemUsers"
          ];
          users.users = systemConfig.systemUsers or { };
          networking.hostName = name;
          home-manager.users = users;
          system.stateVersion = systemConfig.stateVersion;
        }
      ]
      ++ hardwareModules
      ++ [
        ../modules/common
      ];
    };
}
