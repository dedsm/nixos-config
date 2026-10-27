# Shared by both host builders: system fonts, the nix registry, and the
# home-manager bridge that turns each user config in `hc` into a
# home-manager.users entry.
attrs@{
  config,
  pkgs,
  lib,
  hc,
  nixpkgs,
  unstable,
  hyprdynamicmonitors,
  ...
}:
let
  mkHomeManager =
    k: v:
    let
      homeAttrs = attrs // {
        homeManagerConfig = v;
        username = k;
        # The plain-function modules get the system config as `config`, so
        # they cannot read config.home.homeDirectory; hand them the same value
        # home-manager derives it from.
        homeDirectory = config.users.users.${k}.home;
      };
      commonModule = import ./users/common homeAttrs;
    in
    {
      home-manager.users.${k} = lib.mkMerge [
        commonModule
        {
          home.stateVersion = v.stateVersion;
          home.packages = v.packages pkgs;
        }
      ];
    };
in
{
  imports = [ ./fonts.nix ];

  config = lib.mkMerge (
    [
      {
        nix.registry = {
          nixpkgs.flake = nixpkgs;
          unstable.flake = unstable;
        };
        home-manager.backupFileExtension = "home_manager_bak";
        home-manager.sharedModules = [
          hyprdynamicmonitors.homeManagerModules.default
        ];
      }
    ]
    ++ lib.mapAttrsToList mkHomeManager hc
  );
}
