# GTK, Qt, cursor and icon themes on Linux, wired so that DMS stays in charge of
# light/dark: GTK reads DMS's generated colours, and nothing here sets the
# dconf keys DMS owns. See docs/theme.md.
{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf (config.dedsm.theme.enable && pkgs.stdenv.isLinux) {

  qt = {
    enable = true;
    platformTheme.name = "gtk3";
    style.name = "adwaita";
  };

  # NOTE: `color-scheme`, `gtk-theme` and `icon-theme` are deliberately NOT set
  # here, directly or through the gtk options that mirror into them: DMS owns
  # them at runtime. See docs/theme.md, "The one rule".

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

    # Mirrors into the DMS-owned `icon-theme` key; the package is in
    # `home.packages` below.
    iconTheme = null;

    # `theme.name` is left unset on purpose: home-manager mirrors it into BOTH
    # gtk-3.0/settings.ini and the `gtk-theme` dconf key, which would re-pin the
    # light variant on every activation and fight DMS, which drives that key
    # itself (adw-gtk3/adw-gtk3-dark, installed by modules/nixos/dms). The
    # package below stays for the Adwaita icon/theme fallbacks.
    theme = null;
  };

  home = {
    # Adwaita/Adwaita-dark, kept as the fallback pair for apps that ask for a
    # theme by name rather than following the `color-scheme` key DMS drives.
    # Papirus: selected per mode by DMS (iconThemeLight/iconThemeDark).
    packages = [
      pkgs.gnome-themes-extra
      pkgs.papirus-icon-theme
    ];

    pointerCursor = {
      package = pkgs.vanilla-dmz;
      gtk = {
        enable = true;
      };
      name = "Vanilla-DMZ";
      size = 24;
    };
  };
}
