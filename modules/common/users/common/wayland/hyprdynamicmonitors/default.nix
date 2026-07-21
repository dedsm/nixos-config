attrs@{ lib, homeManagerConfig, pkgs, hyprdynamicmonitors, ... }: {
  home.hyprdynamicmonitors = {
    enable = true;
    package = hyprdynamicmonitors.packages.${pkgs.stdenv.hostPlatform.system}.default;
    installExamples = false;
    extraFlags = [ "--enable-lid-events" ];
    config = ''
      [general]
      debounce_time_ms = 300
      # Main config is lua now; profiles emit hl.monitor() calls into
      # monitors.lua, which hyprland.lua pulls in via require("monitors").
      # `hyprctl reload` re-executes the config with a fresh lua state (it nils
      # package.loaded), so require() re-reads the rewritten file. Auto-reload
      # alone is unreliable here because the file is symlinked, not written in
      # place. (hyprctl keyword/source no longer work under the lua parser.)
      destination = "$HOME/.config/hypr/monitors.lua"
      # Waybar has a long-standing upstream bug (Alexays/Waybar#3975, #4823)
      # where a monitor hotplug desyncs its Hyprland IPC/tray connection: the
      # bar goes unresponsive until the service is restarted. Since this only
      # fires on an actual profile transition (not every udev event), restart
      # waybar alongside the reload rather than chase the upstream bug here.
      post_apply_exec = "hyprctl reload && systemctl --user restart waybar.service"

      [fallback_profile]
      config_file = "hyprconfigs/fallback.lua"
      config_file_type = "static"

      [profiles.laptop_only]
      config_file = "hyprconfigs/laptop_only.lua"
      config_file_type = "static"

      [[profiles.laptop_only.conditions.required_monitors]]
      name = "eDP-1"

      # Docked upstairs - lid open: all 3 screens
      [profiles.docked_lid_open]
      config_file = "hyprconfigs/docked_lid_open.lua"
      config_file_type = "static"

      [profiles.docked_lid_open.conditions]
      lid_state = "Opened"

      [[profiles.docked_lid_open.conditions.required_monitors]]
      description = "LG Electronics LG ULTRAFINE 110NTZN4L965"

      [[profiles.docked_lid_open.conditions.required_monitors]]
      description = "LG Electronics LG ULTRAFINE 110NTMX4M035"

      # Docked upstairs - lid closed: externals only
      [profiles.docked_lid_closed]
      config_file = "hyprconfigs/docked_lid_closed.lua"
      config_file_type = "static"

      [profiles.docked_lid_closed.conditions]
      lid_state = "Closed"

      [[profiles.docked_lid_closed.conditions.required_monitors]]
      description = "LG Electronics LG ULTRAFINE 110NTZN4L965"

      [[profiles.docked_lid_closed.conditions.required_monitors]]
      description = "LG Electronics LG ULTRAFINE 110NTMX4M035"

      # Docked downstairs - lid open: LG + laptop
      [profiles.docked_downstairs_lid_open]
      config_file = "hyprconfigs/docked_downstairs_lid_open.lua"
      config_file_type = "static"

      [profiles.docked_downstairs_lid_open.conditions]
      lid_state = "Opened"

      [[profiles.docked_downstairs_lid_open.conditions.required_monitors]]
      name = "eDP-1"

      [[profiles.docked_downstairs_lid_open.conditions.required_monitors]]
      description = "LG Electronics LG Ultra HD 0x0000E0D7"

      # Docked downstairs - lid closed: LG only
      [profiles.docked_downstairs_lid_closed]
      config_file = "hyprconfigs/docked_downstairs_lid_closed.lua"
      config_file_type = "static"

      [profiles.docked_downstairs_lid_closed.conditions]
      lid_state = "Closed"

      [[profiles.docked_downstairs_lid_closed.conditions.required_monitors]]
      description = "LG Electronics LG Ultra HD 0x0000E0D7"

      [profiles.avr]
      config_file = "hyprconfigs/avr.lua"
      config_file_type = "static"

      [[profiles.avr.conditions.required_monitors]]
      name = "eDP-1"

      [[profiles.avr.conditions.required_monitors]]
      description = "Sony LG TV SSCR2 0x00000101"
    '';
    extraFiles = {
      "hyprdynamicmonitors/hyprconfigs/laptop_only.lua" = pkgs.writeText "laptop_only.lua" ''
        hl.monitor({ output = "eDP-1", mode = "2256x1504@59.999", position = "0x0", scale = 1.333333 })
      '';
      "hyprdynamicmonitors/hyprconfigs/docked_lid_open.lua" = pkgs.writeText "docked_lid_open.lua" ''
        hl.monitor({ output = "desc:LG Electronics LG ULTRAFINE 110NTZN4L965", mode = "3840x2160@59.996", position = "0x0", scale = 1.5 })
        hl.monitor({ output = "desc:LG Electronics LG ULTRAFINE 110NTMX4M035", mode = "3840x2160@59.996", position = "2560x0", scale = 1.5 })
        hl.monitor({ output = "eDP-1", mode = "2256x1504@59.999", position = "5120x0", scale = 1.333333 })
      '';
      "hyprdynamicmonitors/hyprconfigs/docked_lid_closed.lua" = pkgs.writeText "docked_lid_closed.lua" ''
        hl.monitor({ output = "eDP-1", disabled = true })
        hl.monitor({ output = "desc:LG Electronics LG ULTRAFINE 110NTZN4L965", mode = "3840x2160@59.996", position = "0x0", scale = 1.5 })
        hl.monitor({ output = "desc:LG Electronics LG ULTRAFINE 110NTMX4M035", mode = "3840x2160@59.996", position = "2560x0", scale = 1.5 })
      '';
      "hyprdynamicmonitors/hyprconfigs/docked_downstairs_lid_open.lua" = pkgs.writeText "docked_downstairs_lid_open.lua" ''
        hl.monitor({ output = "desc:LG Electronics LG Ultra HD 0x0000E0D7", mode = "3840x2160@60", position = "0x0", scale = 1.5 })
        hl.monitor({ output = "eDP-1", mode = "2256x1504@59.999", position = "2560x0", scale = 1.333333 })
      '';
      "hyprdynamicmonitors/hyprconfigs/docked_downstairs_lid_closed.lua" = pkgs.writeText "docked_downstairs_lid_closed.lua" ''
        hl.monitor({ output = "eDP-1", disabled = true })
        hl.monitor({ output = "desc:LG Electronics LG Ultra HD 0x0000E0D7", mode = "3840x2160@60", position = "0x0", scale = 1.5 })
      '';
      "hyprdynamicmonitors/hyprconfigs/avr.lua" = pkgs.writeText "avr.lua" ''
        hl.monitor({ output = "desc:Sony LG TV SSCR2 0x00000101", mode = "1920x1080@60", position = "0x0", scale = 1 })
        hl.monitor({ output = "eDP-1", mode = "2256x1504@59.999", position = "1920x0", scale = 1.333333 })
      '';
      "hyprdynamicmonitors/hyprconfigs/fallback.lua" = pkgs.writeText "fallback.lua" ''
        hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
      '';
    };
  };
}
