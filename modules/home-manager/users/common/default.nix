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
  sway = import ./sway attrs;
  git = import ./git attrs;
in lib.mkMerge [
  tmux
  nvim
  zsh
  kdeconnect
  lorri
  mako
  network-manager
  bluetooth
  sway
  git
]
