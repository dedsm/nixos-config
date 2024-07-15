{ lib, hyprland, homeManagerConfig, unstablePkgs, overlaidPkgs, pkgs, ... }:
with lib;
mkIf homeManagerConfig.hyprland.enable {
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = true;
    systemd.variables = [ "--all" ];
    package = hyprland.packages.${pkgs.system}.hyprland.override {
      # debug = true;
    };
    settings = {
      "$terminal" = "${pkgs.foot}/bin/foot";
      "$browser" = "firefox-developer-edition";
      "$mod" = "SUPER";
      exec-once = [
        "mako"
        "dropbox"
        "avizo-service"
        "solaar -w hide"
        "wl-paste -t text --watch clipman store --no-persist"
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        "sleep 5 && ${unstablePkgs.synology-drive-client}/bin/synology-drive"
        "${pkgs.kdePackages.kwallet-pam}/libexec/pam_kwallet_init"
      ];
      #debug = {
        #enable_stdout_logs = true;
      #};
      misc = {
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
        focus_on_activate = true;
      };
      master = {
        new_status = "slave";
        #new_is_master = false;
        no_gaps_when_only = 1;
      };
      decoration = { rounding = 0; };
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
          "liner, 1, 1, 1, 1"
        ];
        animation = [
          "windows, 1, 6, wind, slide"
          "windowsIn, 1, 6, winIn, slide"
          "windowsOut, 1, 5, winOut, slide"
          "windowsMove, 1, 5, wind, slide"
          "border, 1, 1, liner"
          "borderangle, 1, 30, liner, loop"
          "fade, 1, 10, default"
          "workspaces, 1, 5, wind"
        ];
      };
      env = [
        "GDK_SCALE,2"
        "GDK_BACKEND,wayland,x11"
        "SDL_VIDEODRIVER,wayland"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
        "_JAVA_AWT_WM_NONREPARENTING,1"
        "MOZ_ENABLE_WAYLAND,1"
        "NIXOS_OZONE_WL,1"
      ];
      bindm = [ "$mod, mouse:272, movewindow" "$mod, mouse:273, resizewindow" ];
      binde = [
        ", XF86MonBrightnessDown, exec, lightctl down 1"
        ", XF86MonBrightnessUp, exec, lightctl up 1"

        ", XF86AudioRaiseVolume, exec, volumectl + 1"
        ", XF86AudioLowerVolume, exec, volumectl - 1"
      ];
      bind = [
        "ALT SHIFT, W, exec, $browser"
        "ALT SHIFT, F, exec, chromium"
        "ALT SHIFT, S, exec, slack"
        "ALT SHIFT, P, exec, nautilus"
        "ALT SHIFT, C, exec, gnome-calculator"
        "CTRL ALT, L, exec, swaylock -fF -c 000000"
        "$mod, P, exec, bemenu-run"
        "$mod, X, exec, playerctl play-pause"
        "$mod, Z, exec, playerctl previous"
        "$mod, C, exec, playerctl next"
        "$mod, T, togglefloating"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioPrev, exec, playerctl previous"
        ", XF86AudioNext, exec, playerctl next"
        ", Print, exec, grimblast copy area"
        ", XF86AudioMute, exec, volumectl %"
        "$mod SHIFT, RETURN, exec, $terminal"
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
      ] ++ (
        # workspaces
        # binds $mod + [shift +] {1..10} to [move to] workspace {1..10}
        builtins.concatLists (builtins.genList (x:
          let
            ws = let c = (x + 1) / 10; in builtins.toString (x + 1 - (c * 10));
          in [
            "$mod, ${ws}, focusworkspaceoncurrentmonitor, ${toString (x + 1)}"
            "$mod SHIFT, ${ws}, movetoworkspacesilent, ${toString (x + 1)}"
          ]) 10));
    };
  };
}
