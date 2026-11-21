# The Linux desktop session's applications and plumbing: Firefox, the foot
# terminal, nix-index's command-not-found, XDG/MIME, tray icons and 1Password's
# autostart. How the desktop looks (GTK, Qt, cursor, icons) is the `theme`
# module's job, in ../theme/toolkits.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  solarizedTerminal = (import ../theme/solarized.nix).terminal;

  # foot's names for a mode's colours: `cursor` is "<text> <cursor>", and the
  # 16 ANSI colours are regular0..7 then bright0..7.
  footColors =
    mode:
    {
      inherit (mode) background foreground;
      cursor = "${mode.cursorText} ${mode.cursor}";
    }
    // lib.listToAttrs (
      lib.imap0 (
        i: color:
        lib.nameValuePair (if i < 8 then "regular${toString i}" else "bright${toString (i - 8)}") color
      ) mode.ansi
    );
in
{
  options.dedsm.linux-desktop.enable = lib.mkEnableOption "the Linux desktop session's applications and plumbing";

  config = lib.mkIf config.dedsm.linux-desktop.enable {
    programs = {
      firefox = {
        enable = true;
        package = pkgs.firefox-devedition;
        # Adopt Firefox 147+ XDG layout (~/.config/mozilla/firefox). Fresh machines
        # use XDG automatically; existing ~/.mozilla profiles stay legacy (no auto-migration).
        configPath = "${config.home.homeDirectory}/.config/mozilla/firefox";
      };

      nix-index = {
        enable = true;
        enableZshIntegration = true;
      };

      foot = {
        enable = true;

        settings = {
          main = {
            term = "foot";
            font = "InconsolataGo Nerd Font Mono:size=12";
            dpi-aware = "no";
            # Not `initial-color-theme` directly: that takes a literal `dark` or
            # `light`, and a pinned value is wrong half the day — a foot started
            # while the system is dark painted light and was corrected a moment
            # later by the zsh hook below. The include is one line, rewritten by
            # the `theme` module on every mode change and seeded at activation, so
            # a new terminal opens in the mode that is already current.
            include = "~/.config/foot/mode.ini";
          };

          scrollback = {
            lines = 10000;
          };

          mouse = {
            hide-when-typing = "yes";
          };

          tweak = {
            delayed-render-lower = 5000000;
            delayed-render-upper = 16000000;
          };

          # Solarized Light and Dark, from the shared palette
          # (modules/home/theme/solarized.nix). foot switches a running
          # terminal to colors-dark on SIGUSR1 and colors-light on SIGUSR2
          # (the theme module sends them; bare [colors] is deprecated).
          colors-light = footColors solarizedTerminal.light;
          colors-dark = footColors solarizedTerminal.dark;
        };
      };
    };

    xsession.preferStatusNotifierItems = true;

    xdg = {
      mime = {
        enable = true;
      };
      enable = true;
    };

    systemd.user.services = {
      _1password = {
        Install = {
          WantedBy = lib.mkForce [ "graphical-session.target" ];
        };
        Unit = {
          After = lib.mkForce [ "graphical-session.target" ];
          PartOf = lib.mkForce [ "graphical-session.target" ];
          Requires = lib.mkForce [ "graphical-session.target" ];
        };
        Service = {
          Restart = "on-failure";
          ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
          ExecStart = "${pkgs.unfree._1password-gui}/bin/1password --silent"; # unfree (lib/pkgs.nix)
        };
      };
    };
  };
}
