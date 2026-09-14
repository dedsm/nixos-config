attrs@{
  lib,
  config,
  homeManagerConfig,
  pkgs,
  username,
  ...
}:
{
  programs = {
    firefox = {
      enable = true;
      package = pkgs.firefox-devedition;
      # Adopt Firefox 147+ XDG layout (~/.config/mozilla/firefox). Fresh machines
      # use XDG automatically; existing ~/.mozilla profiles stay legacy (no auto-migration).
      configPath = "${config.users.users.${username}.home}/.config/mozilla/firefox";
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

        colors-light = {
          # Solarized Light (applied on SIGUSR1 / light mode; bare [colors] is deprecated)
          cursor = "fdf6e3 586e75";
          background = "fdf6e3";
          foreground = "657b83";
          regular0 = "eee8d5"; # base2
          regular1 = "dc322f"; # red
          regular2 = "859900"; # green
          regular3 = "b58900"; # yellow
          regular4 = "268bd2"; # blue
          regular5 = "d33682"; # magenta
          regular6 = "2aa198"; # cyan
          regular7 = "073642"; # base02
          bright0 = "cb4b16"; # orange
          bright1 = "fdf6e3"; # base3
          bright2 = "93a1a1"; # base1
          bright3 = "839496"; # base0
          bright4 = "657b83"; # base00
          bright5 = "6c71c4"; # violet
          bright6 = "586e75"; # base01
          bright7 = "002b36"; # base03
        };

        colors-dark = {
          # Solarized Dark (applied on SIGUSR2 / dark mode; foot renamed colors2 -> colors-dark)
          cursor = "002b36 93a1a1";
          background = "002b36";
          foreground = "839496";
          regular0 = "073642"; # base02
          regular1 = "dc322f"; # red
          regular2 = "859900"; # green
          regular3 = "b58900"; # yellow
          regular4 = "268bd2"; # blue
          regular5 = "d33682"; # magenta
          regular6 = "2aa198"; # cyan
          regular7 = "eee8d5"; # base2
          bright0 = "cb4b16"; # orange
          bright1 = "002b36"; # base03
          bright2 = "586e75"; # base01
          bright3 = "657b83"; # base00
          bright4 = "839496"; # base0
          bright5 = "6c71c4"; # violet
          bright6 = "93a1a1"; # base1
          bright7 = "fdf6e3"; # base3
        };
      };
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk3";
    style.name = "adwaita";
  };

  # NOTE: `color-scheme` and `gtk-theme` are deliberately NOT set here. They are
  # owned exclusively by DankMaterialShell at runtime — see
  # docs/theme.md. Declaring them statically makes every home-manager activation
  # `dconf load` them back to their light values, which the xdg-desktop-portal-gtk
  # Settings backend then broadcasts to every portal-aware app (Firefox, Slack,
  # ...), silently knocking them back to light mid-session.
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      icon-theme = "Papirus";
    };
  };

  gtk = {
    enable = true;
    # The `@import` is what connects GTK3 to the theme chain at all, and it has
    # to be the first rule in the file — GTK ignores an `@import` that follows
    # any other rule. `dank-colors.css` is DMS's matugen output (see
    # matugen/configs/gtk3-{dark,light}.toml in the shell package): it is
    # rewritten in place on every light/dark transition, so importing it is
    # enough to track the schedule — nothing here needs a hook.
    #
    # Without it the file DMS regenerates is simply never loaded. That is not
    # hypothetical: this option is the *only* thing that writes
    # ~/.config/gtk-3.0/gtk.css, so declaring `extraCss` without the import
    # silently severs the link, and GTK3 apps (pinentry's gcr prompter, say)
    # sit on stock light Adwaita while everything else follows the schedule.
    gtk3.extraCss = ''
      @import url("dank-colors.css");

      @binding-set no-emoji {
        unbind "<Control>period";
        unbind "<Control>semicolon";
      }
      entry {
        -gtk-key-bindings: no-emoji;
      }
      textview {
        -gtk-key-bindings: no-emoji;
      }
    '';
    # 26.05: gtk4.theme no longer mirrors gtk.theme; GTK4 apps use libadwaita,
    # which follows the `color-scheme` dconf key DMS drives. Pinning
    # `gtk-application-prefer-dark-theme` in settings.ini here would hard-lock
    # GTK4/libadwaita apps to light regardless of the current mode.
    gtk4.theme = null;
    # libadwaita already gets light/dark right from `color-scheme`, so this is
    # about *colour*, not mode: the same matugen import gives GTK4 apps the
    # Solarized palette the rest of the desktop uses instead of stock Adwaita
    # accents. DMS writes a gtk-4.0/dank-colors.css alongside the GTK3 one.
    gtk4.extraCss = ''
      @import url("dank-colors.css");
    '';
    cursorTheme = {
      package = pkgs.vanilla-dmz;
      name = "Vanilla-DMZ";
      size = 24;
    };

    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus";
    };

    # `theme.name` is left unset on purpose: home-manager mirrors it into BOTH
    # gtk-3.0/settings.ini and the `gtk-theme` dconf key, which would re-pin the
    # light variant on every activation and fight DMS, which drives that key
    # itself (adw-gtk3/adw-gtk3-dark, installed by modules/nixos/dms). The
    # package below stays for the Adwaita icon/theme fallbacks.
    theme = null;
  };

  xsession.preferStatusNotifierItems = true;

  xdg = {
    mime = {
      enable = true;
    };
    enable = true;
  };

  home = {
    # Adwaita/Adwaita-dark, kept as the fallback pair for apps that ask for a
    # theme by name rather than following the `color-scheme` key DMS drives.
    packages = [ pkgs.gnome-themes-extra ];

    pointerCursor = {
      package = pkgs.vanilla-dmz;
      gtk = {
        enable = true;
      };
      name = "Vanilla-DMZ";
      size = 24;
    };
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
        ExecStart = "${pkgs.unfree._1password-gui}/bin/1password --silent";
      };
    };
  };
}
