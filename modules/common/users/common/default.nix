attrs@{
  config,
  pkgs,
  lib,
  ...
}:
let
  tmux = import ./tmux attrs;
  herdr = import ./herdr attrs;
  nvim = import ./nvim attrs;
  zsh = import ./zsh attrs;
  kdeconnect = import ./kdeconnect attrs;
  hyprland = import ./hyprland attrs;
  dms = import ./dms attrs;
  starship = import ./starship attrs;
  git = import ./git attrs;
  gh = import ./gh attrs;
  direnv = import ./direnv attrs;
  fzf = import ./fzf attrs;
  zoxide = import ./zoxide attrs;
  ssh = import ./ssh attrs;
  ghostty = import ./ghostty attrs;
  sketchybar = import ./sketchybar attrs;
  theme = import ./theme attrs;
  anyrun = import ./anyrun attrs;
  claude-code = import ./claude-code attrs;
  playwright = import ./playwright attrs;
  antigravity = import ./antigravity attrs;
  cli-notify = import ./cli-notify attrs;

  defaults = import ./defaults attrs;
in
lib.mkMerge [
  tmux
  herdr
  nvim
  zsh
  kdeconnect
  hyprland
  dms
  starship
  git
  gh
  direnv
  fzf
  zoxide
  ssh
  ghostty
  sketchybar
  theme
  claude-code
  playwright
  antigravity
  cli-notify

  anyrun
  defaults
]
