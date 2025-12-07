{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.git.enable or false) { programs.git = homeManagerConfig.git; }
