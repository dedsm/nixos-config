{ lib, homeManagerConfig, pkgs, ... }:
with lib;
mkIf (homeManagerConfig.ghostty.enable or false) {
  programs.ghostty = {
    enable = true;
    package = pkgs.unstable.ghostty-bin;
    settings = {
      font-family = "InconsolataGo Nerd Font Mono";
      font-size = 14;
      theme = "light:Selenized Light,dark:Selenized Dark";
      cursor-style = "block";
      cursor-style-blink = false;
      # Shell integration otherwise resets the cursor to a bar at the prompt,
      # overriding cursor-style. Disable just that feature to keep the block.
      shell-integration-features = "no-cursor";
    };
  };
}
