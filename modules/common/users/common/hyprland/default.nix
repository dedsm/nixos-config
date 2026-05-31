{
  lib,
  config,
  hyprland,
  homeManagerConfig,
  pkgs,
  ...
}:
with lib;
  mkIf (homeManagerConfig.hyprland.enable or false) (let
    anyrunPkg = pkgs.unstable.anyrun;
    hyprshot-picker = pkgs.writeShellScript "hyprshot-picker" ''
      choice=$(printf "Copy Region\nCopy Window\nCopy Monitor\nSave Region\nSave Window\nSave Monitor" | ${anyrunPkg}/bin/anyrun --plugins ${anyrunPkg}/lib/libstdin.so --show-results-immediately true 2>/dev/null)
      case "$choice" in
        "Copy Region")  ${pkgs.hyprshot}/bin/hyprshot -m region --clipboard-only ;;
        "Copy Window")  ${pkgs.hyprshot}/bin/hyprshot -m window --clipboard-only ;;
        "Copy Monitor") ${pkgs.hyprshot}/bin/hyprshot -m output --clipboard-only ;;
        "Save Region")  ${pkgs.hyprshot}/bin/hyprshot -m region -o ~/Downloads ;;
        "Save Window")  ${pkgs.hyprshot}/bin/hyprshot -m window -o ~/Downloads ;;
        "Save Monitor") ${pkgs.hyprshot}/bin/hyprshot -m output -o ~/Downloads ;;
      esac
    '';
    screencast-inhibit = pkgs.writeShellScript "screencast-inhibit" ''
      ${pkgs.socat}/bin/socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while IFS= read -r line; do
        case "$line" in
          "screencast>>1,"*) swaync-client --inhibitor-add screencast ;;
          "screencast>>0,"*) swaync-client --inhibitor-remove screencast ;;
        esac
      done
    '';
    monitor-by-position = pkgs.writeShellScript "monitor-by-position" ''
      set -euo pipefail
      action="$1"
      slot="$2"
      monitors=$(hyprctl monitors -j)
      count=$(echo "$monitors" | ${pkgs.jq}/bin/jq 'length')
      case "$count" in
        1) idx=0 ;;
        2)
          case "$slot" in
            left)   idx=0 ;;
            center) idx=1 ;;
            right)  exit 0 ;;
            *)      exit 1 ;;
          esac
          ;;
        *)
          case "$slot" in
            left)   idx=0 ;;
            center) idx=$((count / 2)) ;;
            right)  idx=$((count - 1)) ;;
            *)      exit 1 ;;
          esac
          ;;
      esac
      name=$(echo "$monitors" | ${pkgs.jq}/bin/jq -r "sort_by(.x)[$idx].name")
      case "$action" in
        focus) hyprctl dispatch focusmonitor "$name" ;;
        move)  hyprctl dispatch movewindow "mon:$name" ;;
        *)     exit 1 ;;
      esac
    '';
  in {
    # UWSM-specific environment file for Hyprland
    xdg.configFile."uwsm/env-hyprland".text = ''
      # Wayland toolkit backend variables
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
        source = [ "~/.config/hypr/monitors.conf" ];
        "$terminal" = "${pkgs.foot}/bin/foot";
        "$browser" = "firefox-devedition";
        "$mod" = "SUPER";
        exec-once = [
          "uwsm app -- avizo-service"
          "uwsm app -- solaar -w hide"
          "uwsm app -- wl-paste -t text --watch clipman store --no-persist"
          "uwsm app -- ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
          "uwsm app -- sh -c 'sleep 5 && ${pkgs.unstable.synology-drive-client}/bin/synology-drive'"
          "uwsm app -- ${pkgs.kdePackages.kwallet-pam}/libexec/pam_kwallet_init"
        ] ++ lib.optionals (homeManagerConfig.swaync.enable or false) [
          "uwsm app -- ${screencast-inhibit}"
        ];
        misc = {
          force_default_wallpaper = 0;
          disable_hyprland_logo = true;
          # vfr (variable frame rate) is default-true and moved to debug: in 0.55;
          # no need to set it explicitly.
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
          gaps_in = 2;
          gaps_out = 2;
          resize_on_border = true;
          layout = "master";
        };
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
            "$mod, P, exec, uwsm app -- anyrun"
            "$mod, X, exec, uwsm app -- playerctl play-pause"
            "$mod, Z, exec, uwsm app -- playerctl previous"
            "$mod, C, exec, uwsm app -- playerctl next"
            "$mod, T, togglefloating"
            "$mod, F, fullscreen"
            ", XF86AudioPlay, exec, uwsm app -- playerctl play-pause"
            ", XF86AudioPrev, exec, uwsm app -- playerctl previous"
            ", XF86AudioNext, exec, uwsm app -- playerctl next"
            ", Print, exec, uwsm app -- ${pkgs.hyprshot}/bin/hyprshot -m region --clipboard-only"
            "CTRL, Print, exec, ${hyprshot-picker}"
            ", XF86AudioMute, exec, uwsm app -- volumectl %"
            "$mod SHIFT, RETURN, exec, uwsm app -- $terminal"
            "$mod SHIFT, C, killactive"
            "$mod SHIFT, Q, exit"
            "$mod, RETURN, layoutmsg, swapwithmaster"
            "$mod, W, exec, ${monitor-by-position} focus left"
            "$mod, E, exec, ${monitor-by-position} focus center"
            "$mod, R, exec, ${monitor-by-position} focus right"
            "$mod SHIFT, W, exec, ${monitor-by-position} move left"
            "$mod SHIFT, E, exec, ${monitor-by-position} move center"
            "$mod SHIFT, R, exec, ${monitor-by-position} move right"
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

      # Window rules use the 0.55 named-block form: `windowrule` is now a special
      # category whose first field must be the `name` key. The structured `settings`
      # form renders attrs alphabetically, so it can't guarantee name-first ordering —
      # hence raw extraConfig here. border_size 0 on floating windows replaces the
      # removed general:no_border_on_floating.
      extraConfig = ''
        windowrule {
          name = float-picture
          match:title = ^(.*Picture.*)$
          float = true
        }
        windowrule {
          name = float-calculator
          match:class = org.gnome.Calculator
          float = true
        }
        windowrule {
          name = noborder-floating
          match:float = true
          border_size = 0
        }
      '';
    };
  })
