attrs@{ config, pkgs, lib, ... }:
let
  tmux = import ./tmux attrs;
  nvim = import ./nvim attrs;
  zsh = import ./zsh attrs;
  kdeconnect = import ./kdeconnect attrs;
  lorri = import ./lorri attrs;
  mako = import ./mako attrs;
  bluetooth = import ./bluetooth attrs;
  network-manager = import ./network-manager attrs;
  hyprland = import ./hyprland attrs;
  sway = import ./sway attrs;
  wayland = import ./wayland attrs;
  starship = import ./starship attrs;
  git = import ./git attrs;
  direnv = import ./direnv attrs;
  fzf = import ./fzf attrs;
  zoxide = import ./zoxide attrs;
  ssh = import ./ssh attrs;
  ghostty = import ./ghostty attrs;
  sketchybar = import ./sketchybar attrs;

  defaults = import ./defaults attrs;
in lib.mkMerge [
  tmux
  nvim
  zsh
  kdeconnect
  lorri
  mako
  network-manager
  bluetooth
  hyprland
  sway
  wayland
  starship
  git
  direnv
  fzf
  zoxide
  ssh
  ghostty
  sketchybar

  defaults
]
