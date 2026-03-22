attrs @ {
  lib,
  homeManagerConfig,
  pkgs,
  username,
  ...
}: {
  programs = {
    firefox = {
      enable = true;
      package = pkgs.unstable.firefox-devedition;
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
        };

        scrollback = {lines = 10000;};

        mouse = {hide-when-typing = "yes";};

        tweak = {
          delayed-render-lower = 5000000;
          delayed-render-upper = 16000000;
        };

        colors = {
          # Solarized Light (Default)
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

        colors2 = {
          # Solarized Dark (Alternative - SIGUSR2)
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

  gtk = {
    enable = true;
    cursorTheme = {
      package = pkgs.vanilla-dmz;
      name = "Vanilla-DMZ";
      size = 24;
    };

    iconTheme = {
      package = pkgs.hicolor-icon-theme;
      name = "hicolor";
    };

    theme = {
      package = pkgs.gnome-themes-extra;
      name = "Adwaita";
    };
  };

  xsession.preferStatusNotifierItems = true;

  xdg = {
    mime = {enable = true;};
    enable = true;
  };

  home = {
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
