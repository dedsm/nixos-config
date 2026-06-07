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
    # Hyprland 0.55+ parses `hyprctl dispatch` arguments as Lua, so the dispatch
    # calls below use the lua-expression form (hl.dsp.*), not the legacy names.
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
        focus) hyprctl dispatch "hl.dsp.focus({ monitor = \"$name\" })" ;;
        move)  hyprctl dispatch "hl.dsp.window.move({ monitor = \"$name\" })" ;;
        *)     exit 1 ;;
      esac
    '';
    # Workspace binds: $mod + [shift +] {1..10} to [move to] workspace {1..10}.
    # Key "0" maps to workspace 10. Rendered as lua hl.bind calls.
    workspaceBinds = lib.concatStringsSep "\n" (builtins.concatLists (builtins.genList (x: let
      ws = let c = (x + 1) / 10; in builtins.toString (x + 1 - (c * 10));
      n = toString (x + 1);
    in [
      ''hl.bind(mod .. " + ${ws}", hl.dsp.focus({ workspace = ${n}, on_current_monitor = true }))''
      ''hl.bind(mod .. " + SHIFT + ${ws}", hl.dsp.window.move({ workspace = ${n} }))''
    ]) 10));
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
      # Hyprland 0.55 deprecated hyprlang in favor of lua; generate hyprland.lua.
      configType = "lua";
      #package = hyprland.packages.${pkgs.system}.hyprland-debug;
      #package = hyprland.packages.${pkgs.system}.hyprland;

      # Declarative option sections render to a single hl.config({...}) call.
      settings = {
        config = {
          misc = {
            force_default_wallpaper = 0;
            disable_hyprland_logo = true;
            # vfr (variable frame rate) is default-true and moved to debug: in 0.55.
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
            touchpad = {
              natural_scroll = true;
            };
          };
          general = {
            border_size = 2;
            gaps_in = 2;
            gaps_out = 2;
            resize_on_border = true;
            layout = "master";
            col = {
              active_border = "rgb(FF0000)";
            };
          };
          xwayland = {
            force_zero_scaling = true;
          };
          render = {
            # int in lua (0 off / 1 on / 2 auto), not a bool.
            direct_scanout = 1;
          };
        };
      };

      # Imperative config (locals, autostart, animations, binds, rules) as raw
      # lua. Rendered after hl.config, so locals are defined before use.
      extraConfig = ''
        local mod = "SUPER"
        local terminal = "${pkgs.foot}/bin/foot"
        local browser = "firefox-devedition"

        -- Dynamic monitor layout, written/applied by hyprdynamicmonitors.
        -- pcall so a missing file at first boot doesn't abort the config.
        pcall(require, "monitors")

        -- Autostart
        hl.on("hyprland.start", function()
          hl.exec_cmd("uwsm app -- avizo-service")
          hl.exec_cmd("uwsm app -- solaar -w hide")
          hl.exec_cmd("uwsm app -- wl-paste -t text --watch clipman store --no-persist")
          hl.exec_cmd("uwsm app -- ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1")
          hl.exec_cmd("uwsm app -- sh -c 'sleep 5 && ${pkgs.unstable.synology-drive-client}/bin/synology-drive'")
          hl.exec_cmd("uwsm app -- ${pkgs.kdePackages.kwallet-pam}/libexec/pam_kwallet_init")
        ${lib.optionalString (homeManagerConfig.swaync.enable or false) ''  hl.exec_cmd("uwsm app -- ${screencast-inhibit}")
        ''}end)

        -- Animation curves
        hl.curve("wind", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
        hl.curve("winIn", { type = "bezier", points = { {0.1, 1.1}, {0.1, 1.1} } })
        hl.curve("winOut", { type = "bezier", points = { {0.3, -0.3}, {0, 1} } })

        -- Animations
        hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "wind", style = "slide" })
        hl.animation({ leaf = "windowsIn", enabled = true, speed = 6, bezier = "winIn", style = "slide" })
        hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "winOut", style = "slide" })
        hl.animation({ leaf = "windowsMove", enabled = true, speed = 5, bezier = "wind", style = "slide" })
        hl.animation({ leaf = "border", enabled = true, speed = 1, bezier = "default" })
        hl.animation({ leaf = "fade", enabled = true, speed = 10, bezier = "default" })
        hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "wind" })

        -- Mouse binds (old bindm)
        hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
        hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

        -- Repeating binds (old binde)
        hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("lightctl down 1"), { repeating = true })
        hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("lightctl up 1"), { repeating = true })
        hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("volumectl + 1"), { repeating = true })
        hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("volumectl - 1"), { repeating = true })

        -- Binds
        hl.bind("ALT + SHIFT + W", hl.dsp.exec_cmd("uwsm app -- " .. browser))
        hl.bind("ALT + SHIFT + F", hl.dsp.exec_cmd("uwsm app -- chromium"))
        hl.bind("ALT + SHIFT + S", hl.dsp.exec_cmd("uwsm app -- slack"))
        hl.bind("ALT + SHIFT + P", hl.dsp.exec_cmd("uwsm app -- nautilus"))
        hl.bind("ALT + SHIFT + C", hl.dsp.exec_cmd("uwsm app -- gnome-calculator"))
        hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd("uwsm app -- ${pkgs.systemd}/bin/loginctl lock-session"))
        hl.bind(mod .. " + P", hl.dsp.exec_cmd("uwsm app -- anyrun"))
        hl.bind(mod .. " + X", hl.dsp.exec_cmd("uwsm app -- playerctl play-pause"))
        hl.bind(mod .. " + Z", hl.dsp.exec_cmd("uwsm app -- playerctl previous"))
        hl.bind(mod .. " + C", hl.dsp.exec_cmd("uwsm app -- playerctl next"))
        hl.bind(mod .. " + T", hl.dsp.window.float())
        hl.bind(mod .. " + F", hl.dsp.window.fullscreen())
        hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("uwsm app -- playerctl play-pause"))
        hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("uwsm app -- playerctl previous"))
        hl.bind("XF86AudioNext", hl.dsp.exec_cmd("uwsm app -- playerctl next"))
        hl.bind("Print", hl.dsp.exec_cmd("uwsm app -- ${pkgs.hyprshot}/bin/hyprshot -m region --clipboard-only"))
        hl.bind("CTRL + Print", hl.dsp.exec_cmd("${hyprshot-picker}"))
        hl.bind("XF86AudioMute", hl.dsp.exec_cmd("uwsm app -- volumectl %"))
        hl.bind(mod .. " + SHIFT + RETURN", hl.dsp.exec_cmd("uwsm app -- " .. terminal))
        hl.bind(mod .. " + SHIFT + C", hl.dsp.window.close())
        -- uwsm sessions must stop via `uwsm stop`, not the exit dispatcher.
        hl.bind(mod .. " + SHIFT + Q", hl.dsp.exec_cmd("uwsm stop"))
        hl.bind(mod .. " + RETURN", hl.dsp.layout("swapwithmaster"))
        hl.bind(mod .. " + W", hl.dsp.exec_cmd("${monitor-by-position} focus left"))
        hl.bind(mod .. " + E", hl.dsp.exec_cmd("${monitor-by-position} focus center"))
        hl.bind(mod .. " + R", hl.dsp.exec_cmd("${monitor-by-position} focus right"))
        hl.bind(mod .. " + SHIFT + W", hl.dsp.exec_cmd("${monitor-by-position} move left"))
        hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("${monitor-by-position} move center"))
        hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd("${monitor-by-position} move right"))
        hl.bind(mod .. " + TAB", hl.dsp.window.cycle_next())
        hl.bind(mod .. " + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }))
        hl.bind(mod .. " + COMMA", hl.dsp.layout("addmaster"))
        hl.bind(mod .. " + PERIOD", hl.dsp.layout("removemaster"))
        hl.bind(mod .. " + SPACE", hl.dsp.layout("orientationcycle left top"))
        ${workspaceBinds}

        -- Window rules. border_size 0 on floating windows replaces the removed
        -- general:no_border_on_floating.
        hl.window_rule({ name = "float-picture", match = { title = "^(.*Picture.*)$" }, float = true })
        hl.window_rule({ name = "float-calculator", match = { class = "org.gnome.Calculator" }, float = true })
        hl.window_rule({ name = "noborder-floating", match = { float = true }, border_size = 0 })
      '';
    };
  })
