{ lib, homeManagerConfig, ... }:
with lib;
mkIf homeManagerConfig.tmux.enable {
  programs.tmux = {
    enable = true;
    baseIndex = 1;
    clock24 = true;
    escapeTime = 0;
    extraConfig = builtins.readFile ./tmux.conf;
    historyLimit = 30000;
    prefix = "C-f";
    resizeAmount = 5;
    terminal = "screen-256color";
    tmuxinator.enable = true;
  };
}
