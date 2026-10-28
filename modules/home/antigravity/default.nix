{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dedsm.antigravity;

  ideEnable = cfg.ide.enable;
  cliEnable = cfg.cli.enable;
  hubEnable = cfg.hub.enable;

  component =
    what:
    lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install ${what} (when antigravity is enabled).";
    };

  # All three components come from the `antigravity-nix` input (see
  # pkgs/default.nix), not nixpkgs. Linux only: the toggle is set in
  # users/david/nixos.nix, and upstream's macOS derivations are experimental and unpack
  # the DMG into `$out/Applications` with nothing on PATH — so enabling this on
  # Darwin would need work first.
  #
  # The IDE keeps credentials in the desktop keyring, and Electron's
  # autodetection doesn't reliably find it outside a GNOME session. The local
  # package takes no `commandLineArgs` argument the way nixpkgs' Electron
  # packages do, so add the flag by wrapping the wrapper it installs.
  # unfree (lib/pkgs.nix)
  idePkg = pkgs.local.antigravity-ide.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/antigravity-ide --add-flags "--password-store=gnome-libsecret"
    '';
  });

in
{
  options.dedsm.antigravity = {
    enable = lib.mkEnableOption "Google Antigravity";
    hub.enable = component "the Antigravity 2.0 hub app";
    ide.enable = component "the legacy Antigravity IDE";
    cli.enable = component "the agy CLI";
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      lib.optional hubEnable pkgs.local.antigravity-hub # unfree (lib/pkgs.nix)
      ++ lib.optional ideEnable idePkg
      ++ lib.optional cliEnable pkgs.local.antigravity-cli; # unfree (lib/pkgs.nix)

    # The rtk/direnv run_command hook plugin is installed by the agent-harness
    # module, not here. See docs/agent-harness.md.
  };
}
