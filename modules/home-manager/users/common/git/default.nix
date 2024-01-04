{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.git.enable { programs.git = homeManagerConfig.git; }
