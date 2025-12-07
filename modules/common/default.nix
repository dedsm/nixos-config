attrs@{ config, pkgs, lib, hc, ... }:
let
  mkHomeManager = k: v:
    let
      homeAttrs = attrs // { homeManagerConfig = v; };
      commonModule = import ./users/common homeAttrs;
    in {
      home-manager.users.${k} = lib.mkMerge [
        commonModule
        {
          home.stateVersion = v.stateVersion;
          home.packages = v.packages pkgs;
        }
        (lib.mkIf (v ? home && v.home ? homeDirectory) {
          home.homeDirectory = v.home.homeDirectory;
        })
      ];
    };
in lib.mkMerge (lib.mapAttrsToList mkHomeManager hc)
