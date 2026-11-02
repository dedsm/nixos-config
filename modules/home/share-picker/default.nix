# A macOS-style screen share picker: buttons over each window and monitor, in
# place of hyprland-share-picker. See docs/share-picker.md.
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  cfg = config.dedsm.sharePicker;

  shellDir = pkgs.runCommand "share-picker-shell" { } ''
    mkdir -p $out
    cp ${./shell.qml} $out/shell.qml
    cp ${./PickerButton.qml} $out/PickerButton.qml
  '';

  package = pkgs.writeShellApplication {
    name = "share-picker";
    runtimeInputs = [
      # The same Quickshell as Dux Shell, so its Qt matches.
      pkgs.unstable.quickshell
      osConfig.programs.hyprland.package
      # The fallback, hyprland-share-picker.
      osConfig.programs.hyprland.portalPackage
      pkgs.coreutils
      pkgs.jq
      pkgs.util-linux
    ];
    # Runs the same way from a terminal, with --preview.
    excludeShellChecks = [ "SC2016" ];
    text = builtins.replaceStrings [ "@shellDir@" ] [ "${shellDir}" ] (
      builtins.readFile ./share-picker.sh
    );
  };
in
{
  options.dedsm.sharePicker = {
    enable = lib.mkEnableOption "the overlay screen share picker";
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = package;
      description = "The picker, for `share-picker --preview`.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];

    xdg.configFile."hypr/xdph.conf" = {
      text = ''
        screencopy {
          custom_picker_binary = ${lib.getExe package}
        }
      '';
      # xdph reads this once, at start.
      onChange = ''
        ${pkgs.systemd}/bin/systemctl --user try-restart xdg-desktop-portal-hyprland.service || true
      '';
    };
  };
}
