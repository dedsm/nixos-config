attrs@{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
let
  # Hyprland 0.55+ hyprctl dispatch takes a Lua expression; dpms needs a
  # table arg — a bare string like dpms("on") silently means "toggle"
  dpms = action: "${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.dpms({ action = \"${action}\" })'";

  # Make sure the session is locked before it sleeps. It used to have to
  # *replace* a running locker with a password-only one — that is now the
  # fprintd gate's job (dedsm.fingerprintPolicy), re-checked on the VerifyStart
  # hyprlock issues on every resume, so a locker that was up before the window
  # lapsed stops accepting fingerprints without being restarted. What is left
  # is the easy half: start a locker if none is running. hypridle holds a sleep
  # inhibitor until this exits, so the wait keeps the machine awake until the
  # locker is up. See docs/login-flow.md.
  sleep-lock = pkgs.writeShellScript "hyprlock-sleep-lock" ''
    ${pkgs.procps}/bin/pgrep -x hyprlock >/dev/null && exit 0

    ${pkgs.hyprlock}/bin/hyprlock --immediate-render &

    # Let the locker bind and draw before releasing the inhibitor.
    for _ in $(${pkgs.coreutils}/bin/seq 30); do
      ${pkgs.procps}/bin/pgrep -x hyprlock >/dev/null && break
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    ${pkgs.coreutils}/bin/sleep 0.5
  '';
in
{
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
