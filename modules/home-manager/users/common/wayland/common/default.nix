attrs@{ lib, homeManagerConfig, unfreePkgs, pkgs, ... }: {
  programs = {
    firefox = {
      enable = true;
      package = pkgs.firefox-devedition-bin;
    };

    autojump = {
      enable = true;
      enableZshIntegration = true;
    };

    direnv = {
      enable = true;
      enableZshIntegration = true;
      stdlib = builtins.readFile ./direnvrc;
      config = { global = { warn_timeout = "3000h"; }; };
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    nix-index = {
      enable = true;
      enableZshIntegration = true;
    };

    ssh = {
      enable = true;
      controlMaster = "auto";
      controlPath = "~/.ssh/sockets/%r@%h-%p";
      controlPersist = "60";
      hashKnownHosts = true;
      extraConfig = ''
        UseRoaming no
        SetEnv TERM=xterm-256color
      '';
    };

    foot = {
      enable = true;

      settings = {
        main = {
          term = "foot";
          font = "InconsolataGo Nerd Font Mono:size=10";
          dpi-aware = "no";
        };

        scrollback = { lines = 10000; };

        mouse = { hide-when-typing = "yes"; };

        cursor = { color = "fdf6e3 586e75"; };

        colors = {
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
    platformTheme = "gtk3";
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
      package = pkgs.gnome.gnome-themes-extra;
      name = "Adwaita";
    };
  };

  xsession.preferStatusNotifierItems = true;

  xdg = { mime = { enable = true; }; };

  home = {
    file = {
      ssh_sockets = {
        target = ".ssh/sockets/.nixkeep";
        text = "SSH sockets directory";
      };
    };
    pointerCursor = {
      package = pkgs.vanilla-dmz;
      gtk = { enable = true; };
      name = "Vanilla-DMZ";
      size = 24;
    };
  };

  systemd.user.services = {
    _1password = {
      Install = { WantedBy = lib.mkForce [ "graphical-session.target" ]; };
      Unit = {
        After = lib.mkForce [ "graphical-session.target" "waybar.service" ];
        PartOf = lib.mkForce [ "graphical-session.target" ];
        Requires = lib.mkForce [ "graphical-session.target" "waybar.service" ];
      };
      Service = {
        Restart = "Always";
        ExecStart = "${unfreePkgs._1password-gui}/bin/1password --silent";
      };
    };
  };
}
