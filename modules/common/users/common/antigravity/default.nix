{ lib, homeManagerConfig, pkgs, ... }:
let
  cfg = homeManagerConfig.antigravity or {};
  enable = cfg.enable or false;
  ideEnable = cfg.ide.enable or true;
  cliEnable = cfg.cli.enable or true;
  useUpstream = cfg.useUpstream or false;

  isLinux = pkgs.stdenv.isLinux;

  versionInfo = lib.importJSON ./version.json;

  pinnedIde = pkgs.unstable.callPackage ./ide.nix { versionInfo = versionInfo.ide; };
  pinnedCli = pkgs.unstable.callPackage ./cli.nix { versionInfo = versionInfo.cli; };

  # Once nixpkgs lands the rename + 2.x bump and the CLI package, flip useUpstream
  # to consume those directly instead of the pinned builds in this module.
  idePkg =
    if useUpstream then
      pkgs.unstable.antigravity-ide or pkgs.unstable.antigravity
    else
      pinnedIde;

  cliPkg =
    if useUpstream then
      pkgs.unstable.antigravity-cli or pinnedCli
    else
      pinnedCli;

in
lib.mkIf (enable && isLinux) {
  home.packages =
    lib.optional ideEnable idePkg
    ++ lib.optional cliEnable cliPkg;
}
