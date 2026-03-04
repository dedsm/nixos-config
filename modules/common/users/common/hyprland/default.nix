{
  lib,
  config,
  hyprland,
  homeManagerConfig,


  pkgs,
  ...
}:
with lib;
  mkIf (homeManagerConfig.hyprland.enable or false) {
    # UWSM-specific environment file for Hyprland
    xdg.configFile."uwsm/env-hyprland".text = ''
      # Wayland toolkit backend variables
      export GDK_SCALE=2
      export GDK_BACKEND=wayland,x11
      export SDL_VIDEODRIVER=wayland
      export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
      export _JAVA_AWT_WM_NONREPARENTING=1
      export MOZ_ENABLE_WAYLAND=1
      export NIXOS_OZONE_WL=1
    '';
    
    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = false;
      #package = hyprland.packages.${pkgs.system}.hyprland-debug;
      #package = hyprland.packages.${pkgs.system}.hyprland;
      settings = {
        "$terminal" = "${pkgs.foot}/bin/foot";
        "$browser" = "firefox-devedition";
        "$mod" = "SUPER";
        exec-once = [
          "uwsm app -- mako"
          "uwsm app -- dropbox"
          "uwsm app -- avizo-service"
          "uwsm app -- solaar -w hide"
          "uwsm app -- wl-paste -t text --watch clipman store --no-persist"
          "uwsm app -- ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
          "uwsm app -- sh -c 'sleep 5 && ${pkgs.unstable.synology-drive-client}/bin/synology-drive'"
          "uwsm app -- ${pkgs.kdePackages.kwallet-pam}/libexec/pam_kwallet_init"
        ];
        misc = {
          force_default_wallpaper = 0;
          disable_hyprland_logo = true;
          vfr = true;
          vrr = 1;
        };
        master = {
          new_status = "slave";
        };
        decoration = {
          rounding = 0;
          blur = {enabled = false;};
          shadow = {enabled = false;};
        };
        input = {
          kb_layout = "us";
          kb_variant = "altgr-intl";
          kb_model = "pc105";
          kb_options = "caps:super";
          numlock_by_default = true;
        };
        "input:touchpad" = {
          natural_scroll = true;
        };
        general = {
          border_size = 2;
          "col.active_border" = "0xffff0000";
          no_border_on_floating = true;
          gaps_in = 2;
          gaps_out = 2;
          resize_on_border = true;
          layout = "master";
        };
        windowrulev2 = [
          "float, title:^(.*Picture.*)$"
          "float, class:(org.gnome.Calculator)"
        ];
        xwayland = {
          force_zero_scaling = true;
        };
        animations = {
          bezier = [
            "wind, 0.05, 0.9, 0.1, 1.05"
            "winIn, 0.1, 1.1, 0.1, 1.1"
            "winOut, 0.3, -0.3, 0, 1"
          ];
          animation = [
            "windows, 1, 6, wind, slide"
            "windowsIn, 1, 6, winIn, slide"
            "windowsOut, 1, 5, winOut, slide"
            "windowsMove, 1, 5, wind, slide"
            "border, 1, 1, default"
            "fade, 1, 10, default"
            "workspaces, 1, 5, wind"
          ];
        };
        render = {
          direct_scanout = true;
        };
        bindm = ["$mod, mouse:272, movewindow" "$mod, mouse:273, resizewindow"];
        binde = [
          ", XF86MonBrightnessDown, exec, lightctl down 1"
          ", XF86MonBrightnessUp, exec, lightctl up 1"

          ", XF86AudioRaiseVolume, exec, volumectl + 1"
          ", XF86AudioLowerVolume, exec, volumectl - 1"
        ];
        bind =
          [
            "ALT SHIFT, W, exec, uwsm app -- $browser"
            "ALT SHIFT, F, exec, uwsm app -- chromium"
            "ALT SHIFT, S, exec, uwsm app -- slack"
            "ALT SHIFT, P, exec, uwsm app -- nautilus"
            "ALT SHIFT, C, exec, uwsm app -- gnome-calculator"
            "CTRL ALT, L, exec, uwsm app -- ${pkgs.systemd}/bin/loginctl lock-session"
            "$mod, P, exec, uwsm app -- bemenu-run"
            "$mod, X, exec, uwsm app -- playerctl play-pause"
            "$mod, Z, exec, uwsm app -- playerctl previous"
            "$mod, C, exec, uwsm app -- playerctl next"
            "$mod, T, togglefloating"
            "$mod, F, fullscreen"
            ", XF86AudioPlay, exec, uwsm app -- playerctl play-pause"
            ", XF86AudioPrev, exec, uwsm app -- playerctl previous"
            ", XF86AudioNext, exec, uwsm app -- playerctl next"
            ", Print, exec, uwsm app -- grimblast copy area"
            ", XF86AudioMute, exec, uwsm app -- volumectl %"
            "$mod SHIFT, RETURN, exec, uwsm app -- $terminal"
            "$mod SHIFT, C, killactive"
            "$mod SHIFT, Q, exit"
            "$mod, RETURN, layoutmsg, swapwithmaster"
            "$mod, W, focusmonitor, l"
            "$mod, E, focusmonitor, r"
            "$mod SHIFT, W, movewindow, mon:l"
            "$mod SHIFT, E, movewindow, mon:r"
            "$mod, TAB, cyclenext"
            "$mod SHIFT, TAB, cyclenext, prev"
            "$mod, COMMA, layoutmsg, addmaster"
            "$mod, PERIOD, layoutmsg, removemaster"
            "$mod, SPACE, layoutmsg, orientationcycle left top"
          ]
          ++ (
            # workspaces
            # binds $mod + [shift +] {1..10} to [move to] workspace {1..10}
            builtins.concatLists (builtins.genList (x: let
              ws = let c = (x + 1) / 10; in builtins.toString (x + 1 - (c * 10));
            in [
              "$mod, ${ws}, focusworkspaceoncurrentmonitor, ${toString (x + 1)}"
              "$mod SHIFT, ${ws}, movetoworkspacesilent, ${toString (x + 1)}"
            ]) 10)
          );
      };
    };
  }
