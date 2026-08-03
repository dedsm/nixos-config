attrs@{ lib, homeManagerConfig, pkgs, ... }:
let
  # Hyprland 0.55+ hyprctl dispatch takes a Lua expression; dpms needs a
  # table arg — a bare string like dpms("on") silently means "toggle"
  dpms = action: "${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.dpms({ action = \"${action}\" })'";

  # Password is required after suspend: make sure the locker active during
  # sleep is the strict (no-fingerprint) one. Killing a running hyprlock is
  # safe — under ext-session-lock Hyprland keeps the session locked until a
  # new locker attaches. The trailing sleep gives the new instance time to
  # attach before hypridle releases its sleep inhibitor.
  sleep-lock = pkgs.writeShellScript "hyprlock-sleep-lock" ''
    ${pkgs.procps}/bin/pkill -x hyprlock || true
    ${pkgs.hyprlock}/bin/hyprlock --immediate-render -c "$HOME/.config/hypr/hyprlock-strict.conf" &
    ${pkgs.coreutils}/bin/sleep 1
  '';
in {
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "${pkgs.hyprlock}/bin/hyprlock";
        before_sleep_cmd = "${sleep-lock}";
        after_sleep_cmd = dpms "on";
        ignore_dbus_inhibit = false;
      };
      listener = [
        {
          timeout = 300; # 5 minutes
          on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
          # Not symmetric with on-timeout: this is the recovery path for a
          # display left powered off by the listener below. A dbus inhibit
          # toggle (e.g. Firefox starting/stopping audio) makes hypridle
          # recreate every listener's idle notification, which clears the
          # "idled" flag while the panels are still physically off — that
          # listener's on-resume then never fires. Turning dpms on from *any*
          # resume is idempotent and costs nothing. See docs/login-flow.md.
          on-resume = dpms "on";
        }
        {
          timeout = 600; # 10 minutes
          on-timeout = dpms "off";
          on-resume = dpms "on";
        }
      ];
    };
  };
}
