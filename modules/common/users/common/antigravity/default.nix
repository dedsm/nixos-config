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
  hubEnable = cfg.hub.enable or true;

  # All three components come from the `antigravity-nix` input (see
  # pkgs/default.nix), not nixpkgs. Linux only: the toggle is set in
  # `davidNixos`, and upstream's macOS derivations are experimental and unpack
  # the DMG into `$out/Applications` with nothing on PATH — so enabling this on
  # Darwin would need work first.
  #
  # The IDE keeps credentials in the desktop keyring, and Electron's
  # autodetection doesn't reliably find it outside a GNOME session. The local
  # package takes no `commandLineArgs` argument the way nixpkgs' Electron
  # packages do, so add the flag by wrapping the wrapper it installs.
  idePkg = pkgs.local.antigravity-ide.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/antigravity-ide --add-flags "--password-store=gnome-libsecret"
    '';
  });

in
lib.mkIf enable {
  home.packages =
    lib.optional hubEnable pkgs.local.antigravity-hub
    ++ lib.optional ideEnable idePkg
    ++ lib.optional cliEnable pkgs.local.antigravity-cli;
}
