attrs@{ lib, homeManagerConfig, unstablePkgs, pkgs, ... }: {
  wayland.windowManager.sway = {
    enable = true;
    systemd.enable = true;
    package = null;
    config = {
      menu = "bemenu-run";
      startup = [
        {
          command =
            "dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_SESSION_TYPE";
        }
        { command = "avizo-service"; }
        { command = "mako"; }
        { command = "dropbox"; }
        { command = "solaar -w hide"; }
        { command = "wl-paste -t text --watch clipman store --no-persist"; }
        {
          command =
            "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        }
        { command = "sleep 5 && systemctl --user restart _1password.service"; }
        {
          command =
            "sleep 5 && ${unstablePkgs.synology-drive-client}/bin/synology-drive";
        }
      ];
      modifier = "Mod4";

      keybindings = lib.mkOptionDefault {
        "Mod4+Shift+Return" = "exec ${pkgs.foot}/bin/foot";
        "Mod1+Shift+s" = "exec slack";
        "Mod1+Shift+w" = "exec firefox-developer-edition";
        "Mod1+Shift+f" = "exec chromium";
        "Mod1+Control+l" = "exec swaylock -fF -c 000000";
        "Mod4+Shift+c" = "kill";
        "Mod4+q" = "reload";
        "Mod4+t" = "floating toggle";
        "Mod4+Tab" = "focus next";
        "Mod4+w" = "exec i3xmonadhelper monitor left";
        "Mod4+e" = "exec i3xmonadhelper monitor center";
        "Mod4+r" = "exec i3xmonadhelper monitor right";
        "Mod4+Shift+w" = "exec i3xmonadhelper send_to_output left";
        "Mod4+Shift+e" = "exec i3xmonadhelper send_to_output center";
        "Mod4+Shift+r" = "exec i3xmonadhelper send_to_output right";
        "Mod4+1" = "exec i3xmonadhelper workspace 1";
        "Mod4+2" = "exec i3xmonadhelper workspace 2";
        "Mod4+3" = "exec i3xmonadhelper workspace 3";
        "Mod4+4" = "exec i3xmonadhelper workspace 4";
        "Mod4+5" = "exec i3xmonadhelper workspace 5";
        "Mod4+6" = "exec i3xmonadhelper workspace 6";
        "Mod4+7" = "exec i3xmonadhelper workspace 7";
        "Mod4+8" = "exec i3xmonadhelper workspace 8";
        "Mod4+9" = "exec i3xmonadhelper workspace 9";

        "Mod1+Shift+p" = "exec nautilus";
        "Mod1+Shift+c" = "exec gnome-calculator";
        "Mod4+p" = "exec bemenu-run";

        "Mod4+x" = "exec playerctl play-pause";
        "Mod4+z" = "exec playerctl previous";
        "Mod4+c" = "exec playerctl next";
        "XF86AudioPlay" = "exec playerctl play-pause";
        "XF86AudioPrev" = "exec playerctl previous";
        "XF86AudioNext" = "exec playerctl next";

        "Mod4+Shift+t" = "layout tabbed";

        "Mod4+Return" = null;
        "Mod4+Shift+q" = null;
        "Mod4+d" = null;
        "Mod4+Shift+space" = null;

        "XF86MonBrightnessDown" = "exec lightctl down 1";
        "XF86MonBrightnessUp" = "exec lightctl up 1";

        "XF86AudioRaiseVolume" = "exec volumectl + 1";
        "XF86AudioLowerVolume" = "exec volumectl - 1";
        "XF86AudioMute" = "exec volumectl %";
      };

      floating = {
        criteria = [
          { title = "Firefox .+ Sharing Indicator$"; }
          { app_id = "org.gnome.Calculator"; }
        ];
      };

      bars = [ ];

      seat = { "*" = { xcursor_theme = "Adwaita 24"; }; };

      input = {
        "*" = {
          xkb_layout = "us";
          xkb_variant = "altgr-intl";
          xkb_model = "pc105";
          xkb_options = "caps:super";
          xkb_numlock = "enable";
        };

        "type:touchpad" = {
          tap = "enabled";
          dwt = "enabled";
          natural_scroll = "enabled";
        };
      };
    };
  };
}
