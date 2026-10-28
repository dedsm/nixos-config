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

  # All three components come from unstable, which tracks Google's releases
  # closely enough. Linux only: the toggle is set in users/david/nixos.nix, as
  # macOS doesn't use Antigravity; see docs/antigravity.md.
  #
  # The IDE keeps credentials in the desktop keyring, and Electron's
  # autodetection doesn't reliably find it outside a GNOME session.
  # unfree (lib/pkgs.nix)
  idePkg = pkgs.unstable.antigravity-ide.override {
    commandLineArgs = "--password-store=gnome-libsecret";
  };

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
      lib.optional hubEnable pkgs.unstable.antigravity-hub # unfree (lib/pkgs.nix)
      ++ lib.optional ideEnable idePkg
      ++ lib.optional cliEnable pkgs.unstable.antigravity-cli; # unfree (lib/pkgs.nix)

    # The rtk/direnv run_command hook plugin is installed by the agent-harness
    # module, not here. See docs/agent-harness.md.
  };
}
