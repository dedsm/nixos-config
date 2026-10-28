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
      # The host's own modules, normally just ./hosts/<name>: its hardware,
      # dedsm toggles, users and Home Manager config.
      modules,
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
        { networking.hostName = name; }
      ]
      ++ modules
      ++ [
        ../modules/common
      ];
    };
}
