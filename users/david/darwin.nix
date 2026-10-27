# david on macOS hosts.
{ pkgs, ... }:
{
  imports = [ ./shared.nix ];

  dedsm.ghostty.enable = true;

  home.stateVersion = "25.11";

  # In addition to shared.nix's packages.
  home.packages = with pkgs; [
    ripgrep
    gnupg
    any-nix-shell
    watch
  ];
}
