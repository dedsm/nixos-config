attrs@{ config, pkgs, lib, hc, ... }:
let
  mkHomeManager = k: v:
    let
      homeAttrs = attrs // { 
        homeManagerConfig = v;
        username = k;
      };
      commonModule = import ./users/common homeAttrs;
    in {
      home-manager.backupFileExtension = "home_manager_bak";
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
