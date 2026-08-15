{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
let
  cfg = homeManagerConfig.antigravity or { };
  enable = cfg.enable or false;
  ideEnable = cfg.ide.enable or true;
  cliEnable = cfg.cli.enable or true;

  # The IDE keeps credentials in the desktop keyring on Linux; macOS uses the
  # system keychain and takes no flag.
  idePkg =
    if pkgs.stdenv.isLinux then
      pkgs.unstable.antigravity-ide.override {
        commandLineArgs = "--password-store=gnome-libsecret";
      }
    else
      pkgs.unstable.antigravity-ide;

in
lib.mkIf enable {
  home.packages =
    lib.optional ideEnable idePkg ++ lib.optional cliEnable pkgs.unstable.antigravity-cli;
}
