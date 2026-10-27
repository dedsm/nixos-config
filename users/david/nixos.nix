# david on NixOS hosts.
{ pkgs, ... }:
{
  imports = [ ./shared.nix ];

  dedsm = {
    dms.enable = true;
    defaults.enable = true;
    antigravity.enable = true;
  };

  services.kdeconnect = {
    enable = true;
    indicator = true;
  };

  home.stateVersion = "22.05";

  # In addition to shared.nix's packages.
  home.packages = with pkgs; [
    gnome-themes-extra
    adwaita-icon-theme
    gnome-icon-theme
    gnome-calculator
    nautilus
    eog
    evince
    wl-clipboard
    moonlight-qt
    playerctl
    gimp
    scrot
    grobi
    chromium
    libreoffice
    ffmpeg
    vlc
    ntfs3g
    kubernetes-helm
    digikam
    exiftool
    wireshark
    pavucontrol
    pamixer
    xsane
    imagemagick
    slurp
    grim
    pkgs.unstable.restream
    pkgs.unfree._1password-cli
  ];
}
