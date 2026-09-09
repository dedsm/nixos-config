attrs@{
  lib,
  config,
  hyprland,
  homeManagerConfig,
  pkgs,
  ...
}:
with lib;
let
  # Hyprland-specific, and the last thing the `wayland` grouping held once sway
  # went: it generates monitors.lua for this compositor and nothing else, so it
  # lives here rather than behind a second enable flag that had to be kept in
  # sync with this one.
  hyprdynamicmonitors = import ./hyprdynamicmonitors attrs;
in
mkIf (homeManagerConfig.hyprland.enable or false) (mkMerge [
  hyprdynamicmonitors
  (
    let
      anyrunPkg = pkgs.unstable.anyrun;
      # Prefix patterns, not exact ones: anyrun 26.x emits a plugin's `Stdout` result
      # twice when it runs without a daemon (once as the selection is handled, again
      # from the post-run action on close), so the captured choice comes back doubled
      # and unseparated — "Copy RegionCopy Region" (anyrun-org/anyrun#324, open and
      # unfixed as of 26.6.1). The anyrun module now runs that daemon, which emits a
      # single copy, so this is a safeguard rather than the live workaround: it keeps
      # the picker correct if the daemon is down or the bug is fixed upstream. No
      # entry is a prefix of another, so matching this way stays unambiguous.
      hyprshot-picker = pkgs.writeShellScript "hyprshot-picker" ''
        choice=$(printf "Copy Region\nCopy Window\nCopy Monitor\nSave Region\nSave Window\nSave Monitor" | ${anyrunPkg}/bin/anyrun --plugins ${anyrunPkg}/lib/libstdin.so --show-results-immediately true 2>/dev/null)
        case "$choice" in
          "Copy Region"*)  ${pkgs.hyprshot}/bin/hyprshot -m region --clipboard-only ;;
          "Copy Window"*)  ${pkgs.hyprshot}/bin/hyprshot -m window --clipboard-only ;;
          "Copy Monitor"*) ${pkgs.hyprshot}/bin/hyprshot -m output --clipboard-only ;;
          "Save Region"*)  ${pkgs.hyprshot}/bin/hyprshot -m region -o ~/Downloads ;;
          "Save Window"*)  ${pkgs.hyprshot}/bin/hyprshot -m window -o ~/Downloads ;;
          "Save Monitor"*) ${pkgs.hyprshot}/bin/hyprshot -m output -o ~/Downloads ;;
        esac
      '';
      screencast-inhibit = pkgs.writeShellScript "screencast-inhibit" ''
        ${pkgs.socat}/bin/socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while IFS= read -r line; do
          case "$line" in
            "screencast>>1,"*) dms ipc call notifications enableDoNotDisturbIndefinitely ;;
            "screencast>>0,"*) dms ipc call notifications disableDoNotDisturb ;;
          esac
        done
      '';
      # Workspace binds: $mod + [shift +] {1..10} to [move to] workspace {1..10}.
      # Key "0" maps to workspace 10. Rendered as lua hl.bind calls.
      workspaceBinds = lib.concatStringsSep "\n" (
        builtins.concatLists (
          builtins.genList (
            x:
            let
              ws =
                let
                  c = (x + 1) / 10;
                in
                builtins.toString (x + 1 - (c * 10));
              n = toString (x + 1);
            in
            [
              ''hl.bind(mod .. " + ${ws}", hl.dsp.focus({ workspace = ${n}, on_current_monitor = true }))''
              ''hl.bind(mod .. " + SHIFT + ${ws}", hl.dsp.window.move({ workspace = ${n}, follow = false }))''
            ]
          ) 10
        )
      );
    in
    {
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
              # Black, so the frames before DMS has painted anything match the
              # lock screen that is about to cover them. The shell cannot lock
              # before it starts — it *is* the locker — so a boot always shows
              # the compositor's own background first; this keeps that from
              # being a visibly different colour.
              background_color = "rgb(000000)";
              # The splash line Hyprland renders over its background — the text
              # at the bottom of the screen before DMS has painted anything.
              disable_splash_rendering = true;
              # vfr (variable frame rate) is default-true and moved to debug: in 0.55.
              vrr = 1;
              # Both default to false: without them the *only* thing that can undo
              # hypridle's dpms-off is hypridle's own on-resume, so any hiccup in
              # its idle bookkeeping leaves a black screen on a live, typing-and-
              # authenticating session. Compositor-level backstop; see
              # docs/login-flow.md.
              mouse_move_enables_dpms = true;
              key_press_enables_dpms = true;
              # Let a new locker take over an already-locked session. Off, the
              # locked flag outlives a dead locker and every later lock client is
              # denied, so a session whose locker is gone can only be rebooted
              # out of. Required by DMS's lock-before-suspend and by the recovery
              # bind below. See docs/login-flow.md.
              allow_session_lock_restore = true;
            };
            master = {
              new_status = "slave";
            };
            decoration = {
              rounding = 0;
              blur = {
                enabled = false;
              };
              shadow = {
                enabled = false;
              };
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
              # Default is 15px, which reaches well into the waybar above a
              # window and steals its clicks. 4px is still comfortably grabbable.
              extend_border_grab_area = 4;
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
            -- The boot lock, only under greetd autologin: there the session
            -- starts unattended and this is the actual auth gate. It is
            -- password-only without being told to — the fingerprint window
            -- lives in /run, so nothing has opened it yet this boot
            -- (dedsm.fingerprintPolicy) — and that typed password is also what
            -- unlocks gnome-keyring via PAM.
            hl.exec_cmd("uwsm app -- solaar -w hide")
            -- No polkit agent here: DMS registers one, and polkit allows a single
            -- agent per subject — whichever starts first wins, so autostarting
            -- polkit-gnome left DMS logging "an authentication agent already
            -- exists" and every prompt coming from the GTK dialog instead.
            hl.exec_cmd("uwsm app -- sh -c 'sleep 5 && ${pkgs.unstable.synology-drive-client}/bin/synology-drive'")
            hl.exec_cmd("uwsm app -- ${screencast-inhibit}")
          end)

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

          -- Focus/move the active window to a monitor chosen by physical position.
          -- Monitors are sorted in reading order each press -- top row first, then
          -- left to right within a row -- so it stays correct across hotplug.
          -- Replaces the old bash+jq monitor-by-position script.
          --
          -- Sorting on x alone was enough while every profile was a single row, but
          -- the docked_lid_open profile now parks the laptop *below* the two
          -- externals and centred on their seam (x = 1714). On an x-only sort it
          -- would come second and steal $mod+E from the right-hand LG; keyed on y
          -- first it stays third, so $mod+R is still the laptop.
          --
          -- The row test is exact y equality, which is safe because every profile
          -- states its positions outright and both externals sit at y = 0. Offset
          -- one of them deliberately (to line their bottoms up, say) and they would
          -- split into two rows and the slots would shift.
          local function monitorByPosition(action, slot)
            local mons = hl.get_monitors()
            table.sort(mons, function(a, b)
              if a.y ~= b.y then return a.y < b.y end
              return a.x < b.x
            end)
            local n, idx = #mons, nil
            if n == 1 then idx = 1
            elseif n == 2 then
              if slot == "left" then idx = 1
              elseif slot == "center" then idx = 2
              else return end                       -- right: no-op on dual
            else
              if slot == "left" then idx = 1
              elseif slot == "center" then idx = math.floor(n / 2) + 1
              elseif slot == "right" then idx = n
              else return end
            end
            local name = mons[idx].name
            if action == "focus" then
              hl.dispatch(hl.dsp.focus({ monitor = name }))
            else
              hl.dispatch(hl.dsp.window.move({ monitor = name, follow = false }))
            end
          end

          -- Mouse binds (old bindm)
          hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
          hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

          -- Repeating binds (old binde)
          --
          -- The trailing "" on the brightness calls is the device argument. The
          -- IPC documents it as optional but the running shell requires it
          -- (`function increment(step: string, device: string)`), and a call with
          -- one argument fails with "Too few arguments provided" — silently, from
          -- a keybind. Empty means the default backlight. `audio` takes only the
          -- step, so those calls stay as they are.
          -- DMS owns the OSD for these, and its brightness manager drives DDC on
          -- external monitors as well as the internal backlight — which is what
          -- retired avizo (lightctl/volumectl) along with its service.
          hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd([[dms ipc call brightness decrement 1 ""]]), { repeating = true })
          hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd([[dms ipc call brightness increment 1 ""]]), { repeating = true })
          hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("dms ipc call audio increment 1"), { repeating = true })
          hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("dms ipc call audio decrement 1"), { repeating = true })

          -- Binds
          hl.bind("ALT + SHIFT + W", hl.dsp.exec_cmd("uwsm app -- " .. browser))
          hl.bind("ALT + SHIFT + F", hl.dsp.exec_cmd("uwsm app -- chromium"))
          hl.bind("ALT + SHIFT + S", hl.dsp.exec_cmd("uwsm app -- slack"))
          hl.bind("ALT + SHIFT + P", hl.dsp.exec_cmd("uwsm app -- nautilus"))
          hl.bind("ALT + SHIFT + C", hl.dsp.exec_cmd("uwsm app -- gnome-calculator"))
          hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd("uwsm app -- ${pkgs.systemd}/bin/loginctl lock-session"))
          -- Recovers a locked session whose locker is gone: restarting the shell
          -- brings a new lock client that takes the orphaned lock. `locked` is
          -- required for the bind to run at all while locked; taking the lock
          -- needs misc:allow_session_lock_restore above.
          hl.bind("CTRL + ALT + SHIFT + L", hl.dsp.exec_cmd("systemctl --user restart dms.service"), { locked = true })
          hl.bind(mod .. " + P", hl.dsp.exec_cmd("dms ipc call spotlight toggle"))
          -- The rest of the shell, on keys the layout had free. anyrun stays
          -- installed: the screenshot picker above is built on its stdin plugin.
          hl.bind(mod .. " + V", hl.dsp.exec_cmd("dms ipc call clipboard toggle"))
          hl.bind(mod .. " + N", hl.dsp.exec_cmd("dms ipc call notifications toggle"))
          hl.bind(mod .. " + O", hl.dsp.exec_cmd("dms ipc call control-center toggle"))
          hl.bind(mod .. " + X", hl.dsp.exec_cmd("dms ipc call mpris playPause"))
          hl.bind(mod .. " + Z", hl.dsp.exec_cmd("dms ipc call mpris previous"))
          hl.bind(mod .. " + C", hl.dsp.exec_cmd("dms ipc call mpris next"))
          hl.bind(mod .. " + T", hl.dsp.window.float())
          hl.bind(mod .. " + F", hl.dsp.window.fullscreen())
          hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("dms ipc call mpris playPause"))
          hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("dms ipc call mpris previous"))
          hl.bind("XF86AudioNext", hl.dsp.exec_cmd("dms ipc call mpris next"))
          hl.bind("Print", hl.dsp.exec_cmd("uwsm app -- ${pkgs.hyprshot}/bin/hyprshot -m region --clipboard-only"))
          hl.bind("CTRL + Print", hl.dsp.exec_cmd("${hyprshot-picker}"))
          hl.bind("XF86AudioMute", hl.dsp.exec_cmd("dms ipc call audio mute"))
          hl.bind(mod .. " + SHIFT + RETURN", hl.dsp.exec_cmd("uwsm app -- " .. terminal))
          hl.bind(mod .. " + SHIFT + C", hl.dsp.window.close())
          -- uwsm sessions must stop via `uwsm stop`, not the exit dispatcher.
          hl.bind(mod .. " + SHIFT + Q", hl.dsp.exec_cmd("uwsm stop"))
          hl.bind(mod .. " + RETURN", hl.dsp.layout("swapwithmaster"))
          hl.bind(mod .. " + W",         function() monitorByPosition("focus", "left")   end)
          hl.bind(mod .. " + E",         function() monitorByPosition("focus", "center") end)
          hl.bind(mod .. " + R",         function() monitorByPosition("focus", "right")  end)
          hl.bind(mod .. " + SHIFT + W", function() monitorByPosition("move",  "left")   end)
          hl.bind(mod .. " + SHIFT + E", function() monitorByPosition("move",  "center") end)
          hl.bind(mod .. " + SHIFT + R", function() monitorByPosition("move",  "right")  end)
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
    }
  )
])
