attrs@{ config, pkgs, lib, ... }:
let
  tmux = import ./tmux attrs;
  nvim = import ./nvim attrs;
  zsh = import ./zsh attrs;
  kdeconnect = import ./kdeconnect attrs;
  lorri = import ./lorri attrs;
  swaync = import ./swaync attrs;
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
  theme = import ./theme attrs;
  anyrun = import ./anyrun attrs;
  claude-code = import ./claude-code attrs;
  gemini-cli = import ./gemini-cli attrs;

  defaults = import ./defaults attrs;
in lib.mkMerge [
  tmux
  nvim
  zsh
  kdeconnect
  lorri
  swaync
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
  theme
  claude-code
  gemini-cli

  anyrun
  defaults
]
