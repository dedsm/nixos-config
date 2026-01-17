attrs @ {
  lib,
  homeManagerConfig,
  pkgs,
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
          font = "InconsolataGo Nerd Font Mono:size=10";
          dpi-aware = "no";
        };

        scrollback = {lines = 10000;};

        mouse = {hide-when-typing = "yes";};

        colors = {
          cursor = "fdf6e3 586e75";
          background = "fdf6e3";
          foreground = "657b83";
          regular0 = "eee8d5";
          regular1 = "dc322f";
          regular2 = "859900";
          regular3 = "b58900";
          regular4 = "268bd2";
          regular5 = "d33682";
          regular6 = "2aa198";
          regular7 = "073642";
          bright0 = "cb4b16";
          bright1 = "fdf6e3";
          bright2 = "93a1a1";
          bright3 = "839496";
          bright4 = "657b83";
          bright5 = "6c71c4";
          bright6 = "586e75";
          bright7 = "002b36";
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
        ExecStart = "${pkgs.unfree._1password-gui}/bin/1password --silent";
      };
    };
  };
}
