attrs@{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }: {
  services = {
    swayidle = {
      enable = true;
      events = [
        {
          event = "before-sleep";
          command = "${pkgs.swaylock}/bin/swaylock -fF -c 000000";
        }
        {
          event = "lock";
          command = "${pkgs.swaylock}/bin/swaylock -fF -c 000000";
        }
      ];
      timeouts = [
        {
          timeout = 300;
          command = "${pkgs.swaylock}/bin/swaylock -fF -c 000000";
        }
        {
          timeout = 600;
          command = ''${pkgs.sway}/bin/swaymsg "output * dpms off"'';
          resumeCommand = ''${pkgs.sway}/bin/swaymsg "output * dpms on"'';
        }
      ];
    };
  };
}
