attrs@{ lib, homeManagerConfig, pkgs, ... }:
let
  # Hyprland 0.55+ hyprctl dispatch takes a Lua expression; dpms needs a
  # table arg — a bare string like dpms("on") silently means "toggle"
  dpms = action: "${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.dpms({ action = \"${action}\" })'";

  # Password is required after suspend: replace any running locker with the
  # strict (no-fingerprint) one. Sequenced — kill, wait for exit, then start —
  # because Hyprland denies a second lock client while the first still holds
  # the lock, and a denied replacement leaves the session locked with no
  # locker. Needs misc:allow_session_lock_restore (hyprland module).
  # hypridle holds a sleep inhibitor until this exits, so the waits also keep
  # the machine awake until the strict locker is up.
  sleep-lock = pkgs.writeShellScript "hyprlock-sleep-lock" ''
    waitgone() { # $1 = deciseconds to wait for every hyprlock to exit
      for _ in $(${pkgs.coreutils}/bin/seq "$1"); do
        ${pkgs.procps}/bin/pgrep -x hyprlock >/dev/null || return 0
        ${pkgs.coreutils}/bin/sleep 0.1
      done
      return 1
    }

    if ${pkgs.procps}/bin/pgrep -x hyprlock >/dev/null; then
      ${pkgs.procps}/bin/pkill -x hyprlock || true
      waitgone 20 || { ${pkgs.procps}/bin/pkill -KILL -x hyprlock || true; waitgone 10 || true; }
    fi

    ${pkgs.hyprlock}/bin/hyprlock --immediate-render -c "$HOME/.config/hypr/hyprlock-strict.conf" &

    # Let the new locker bind and draw before releasing the inhibitor.
    for _ in $(${pkgs.coreutils}/bin/seq 30); do
      ${pkgs.procps}/bin/pgrep -x hyprlock >/dev/null && break
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    ${pkgs.coreutils}/bin/sleep 0.5
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
