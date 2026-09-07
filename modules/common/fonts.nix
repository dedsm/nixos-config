# System fonts, shared by both platforms: NixOS installs them into the system
# font path, nix-darwin into /Library/Fonts/Nix Fonts (scoped, so fonts installed
# by hand on macOS are left alone). Wired in from lib/nixos-host.nix and
# lib/darwin-host.nix, not from modules/common/default.nix — that file is the
# home-manager bridge and returns a mkMerge, which cannot carry `imports`.
{ pkgs, ... }:
{
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    dina-font
    proggyfonts
    # DMS renders its UI in "Inter Variable" (pkgs.inter ships InterVariable.ttf
    # under exactly that family name); without it the shell falls back silently.
    inter
    pkgs.unstable.nerd-fonts.inconsolata-go
  ];
}
