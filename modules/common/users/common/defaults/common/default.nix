attrs @ {
  lib,
  config,
  homeManagerConfig,
  pkgs,
  username,
  ...
}: {
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
          # foot's new colors-light/colors-dark model defaults startup to dark;
          # the old [colors] base was light, so pin light to match prior behaviour.
          initial-color-theme = "light";
        };

        scrollback = {lines = 10000;};

        mouse = {hide-when-typing = "yes";};

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
  # owned exclusively by the `theme` module (darkman) at runtime — see
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
    gtk3.extraCss = ''
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
    # which follows the `color-scheme` dconf key darkman drives. Pinning
    # `gtk-application-prefer-dark-theme` in settings.ini here would hard-lock
    # GTK4/libadwaita apps to light regardless of the current mode.
    gtk4.theme = null;
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
    # light Adwaita variant on every activation and fight darkman. The package is
    # still installed below so the Adwaita/Adwaita-dark pair darkman switches
    # between is actually on disk.
    theme = null;
  };

  xsession.preferStatusNotifierItems = true;

  xdg = {
    mime = {enable = true;};
    enable = true;
  };

  home = {
    # Provides both Adwaita and Adwaita-dark for the GTK3 side of darkman's switch.
    packages = [pkgs.gnome-themes-extra];

    pointerCursor = {
      package = pkgs.vanilla-dmz;
      gtk = {enable = true;};
      name = "Vanilla-DMZ";
      size = 24;
    };
  };

  systemd.user.services = {
    _1password = {
      Install = {WantedBy = lib.mkForce ["graphical-session.target"];};
      Unit = {
        After = lib.mkForce ["graphical-session.target"];
        PartOf = lib.mkForce ["graphical-session.target"];
        Requires = lib.mkForce ["graphical-session.target"];
      };
      Service = {
        Restart = "on-failure";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        ExecStart = "${pkgs.unfree._1password-gui}/bin/1password --silent";
      };
    };
  };
}
