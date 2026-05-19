attrs@{ lib, homeManagerConfig, pkgs, hyprdynamicmonitors, ... }: {
  home.hyprdynamicmonitors = {
    enable = true;
    package = hyprdynamicmonitors.packages.${pkgs.stdenv.hostPlatform.system}.default;
    installExamples = false;
    extraFlags = [ "--enable-lid-events" ];
    config = ''
      [general]
      debounce_time_ms = 300
      post_apply_exec = "hyprctl keyword source ~/.config/hypr/monitors.conf"

      [fallback_profile]
      config_file = "hyprconfigs/fallback.conf"
      config_file_type = "static"

      [profiles.laptop_only]
      config_file = "hyprconfigs/laptop_only.conf"
      config_file_type = "static"

      [[profiles.laptop_only.conditions.required_monitors]]
      name = "eDP-1"

      # Docked upstairs - lid open: all 3 screens
      [profiles.docked_lid_open]
      config_file = "hyprconfigs/docked_lid_open.conf"
      config_file_type = "static"

      [profiles.docked_lid_open.conditions]
      lid_state = "Opened"

      [[profiles.docked_lid_open.conditions.required_monitors]]
      description = "LG Electronics LG ULTRAFINE 110NTZN4L965"

      [[profiles.docked_lid_open.conditions.required_monitors]]
      description = "LG Electronics LG ULTRAFINE 110NTMX4M035"

      # Docked upstairs - lid closed: externals only
      [profiles.docked_lid_closed]
      config_file = "hyprconfigs/docked_lid_closed.conf"
      config_file_type = "static"

      [profiles.docked_lid_closed.conditions]
      lid_state = "Closed"

      [[profiles.docked_lid_closed.conditions.required_monitors]]
      description = "LG Electronics LG ULTRAFINE 110NTZN4L965"

      [[profiles.docked_lid_closed.conditions.required_monitors]]
      description = "LG Electronics LG ULTRAFINE 110NTMX4M035"

      # Docked downstairs - lid open: LG + laptop
      [profiles.docked_downstairs_lid_open]
      config_file = "hyprconfigs/docked_downstairs_lid_open.conf"
      config_file_type = "static"

      [profiles.docked_downstairs_lid_open.conditions]
      lid_state = "Opened"

      [[profiles.docked_downstairs_lid_open.conditions.required_monitors]]
      name = "eDP-1"

      [[profiles.docked_downstairs_lid_open.conditions.required_monitors]]
      description = "LG Electronics LG Ultra HD 0x0000E0D7"

      # Docked downstairs - lid closed: LG only
      [profiles.docked_downstairs_lid_closed]
      config_file = "hyprconfigs/docked_downstairs_lid_closed.conf"
      config_file_type = "static"

      [profiles.docked_downstairs_lid_closed.conditions]
      lid_state = "Closed"

      [[profiles.docked_downstairs_lid_closed.conditions.required_monitors]]
      description = "LG Electronics LG Ultra HD 0x0000E0D7"

      [profiles.avr]
      config_file = "hyprconfigs/avr.conf"
      config_file_type = "static"

      [[profiles.avr.conditions.required_monitors]]
      name = "eDP-1"

      [[profiles.avr.conditions.required_monitors]]
      description = "Sony LG TV SSCR2 0x00000101"
    '';
    extraFiles = {
      "hyprdynamicmonitors/hyprconfigs/laptop_only.conf" = pkgs.writeText "laptop_only.conf" ''
        monitor=eDP-1, 2256x1504@59.999, 0x0, 1.333333
      '';
      "hyprdynamicmonitors/hyprconfigs/docked_lid_open.conf" = pkgs.writeText "docked_lid_open.conf" ''
        monitor=desc:LG Electronics LG ULTRAFINE 110NTZN4L965, 3840x2160@59.996, 0x0, 1.5
        monitor=desc:LG Electronics LG ULTRAFINE 110NTMX4M035, 3840x2160@59.996, 2560x0, 1.5
        monitor=eDP-1, 2256x1504@59.999, 5120x0, 1.333333
      '';
      "hyprdynamicmonitors/hyprconfigs/docked_lid_closed.conf" = pkgs.writeText "docked_lid_closed.conf" ''
        monitor=eDP-1, disable
        monitor=desc:LG Electronics LG ULTRAFINE 110NTZN4L965, 3840x2160@59.996, 0x0, 1.5
        monitor=desc:LG Electronics LG ULTRAFINE 110NTMX4M035, 3840x2160@59.996, 2560x0, 1.5
      '';
      "hyprdynamicmonitors/hyprconfigs/docked_downstairs_lid_open.conf" = pkgs.writeText "docked_downstairs_lid_open.conf" ''
        monitor=desc:LG Electronics LG Ultra HD 0x0000E0D7, 3840x2160@60, 0x0, 1.5
        monitor=eDP-1, 2256x1504@59.999, 2560x0, 1.333333
      '';
      "hyprdynamicmonitors/hyprconfigs/docked_downstairs_lid_closed.conf" = pkgs.writeText "docked_downstairs_lid_closed.conf" ''
        monitor=eDP-1, disable
        monitor=desc:LG Electronics LG Ultra HD 0x0000E0D7, 3840x2160@60, 0x0, 1.5
      '';
      "hyprdynamicmonitors/hyprconfigs/avr.conf" = pkgs.writeText "avr.conf" ''
        monitor=desc:Sony LG TV SSCR2 0x00000101, 1920x1080@60, 0x0, 1
        monitor=eDP-1, 2256x1504@59.999, 1920x0, 1.333333
      '';
      "hyprdynamicmonitors/hyprconfigs/fallback.conf" = pkgs.writeText "fallback.conf" ''
        monitor=, preferred, auto, 1
      '';
    };
  };
}
