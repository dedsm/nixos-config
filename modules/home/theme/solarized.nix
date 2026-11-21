# Solarized (https://ethanschoonover.com/solarized/), the palette the whole
# desktop uses. The one place it is spelled out: the theme module (tmux),
# foot (modules/home/linux-desktop) and herdr's theme files (modules/home/herdr)
# all import it. Plain hex without `#`, the form foot takes.
let
  colors = {
    base03 = "002b36";
    base02 = "073642";
    base01 = "586e75";
    base00 = "657b83";
    base0 = "839496";
    base1 = "93a1a1";
    base2 = "eee8d5";
    base3 = "fdf6e3";
    yellow = "b58900";
    orange = "cb4b16";
    red = "dc322f";
    magenta = "d33682";
    violet = "6c71c4";
    blue = "268bd2";
    cyan = "2aa198";
    green = "859900";
  };
in
{
  inherit colors;

  # A terminal's colours, per mode. `ansi` is the 16 ANSI colours in order:
  # 0..7 regular, then 8..15 bright. Light mirrors dark's base tones (base03
  # and base3 swap, base02 and base2, and so on) so every slot keeps its
  # contrast against the background. Slots 8 and 9 are orange and the
  # background tone, the reverse of stock Solarized's bright black and bright
  # red; that is how foot has always been set here. `cursorText` is the
  # character under the cursor; `selection` is for terminals that take one
  # (foot leaves it to inversion).
  terminal = with colors; {
    dark = {
      background = base03;
      foreground = base0;
      cursor = base1;
      cursorText = base03;
      selection = base02;
      ansi = [
        base02
        red
        green
        yellow
        blue
        magenta
        cyan
        base2
        orange
        base03
        base01
        base00
        base0
        violet
        base1
        base3
      ];
    };
    light = {
      background = base3;
      foreground = base00;
      cursor = base01;
      cursorText = base3;
      selection = base2;
      ansi = [
        base2
        red
        green
        yellow
        blue
        magenta
        cyan
        base02
        orange
        base3
        base1
        base0
        base00
        violet
        base01
        base03
      ];
    };
  };
}
