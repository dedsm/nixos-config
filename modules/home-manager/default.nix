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
          home.packages = v.packages;
        }
      ];
    };
in lib.mkMerge (lib.mapAttrsToList mkHomeManager hc)
