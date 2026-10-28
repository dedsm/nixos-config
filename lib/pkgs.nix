# The package set every host and flake output is built from: nixpkgs plus one
# overlay adding pkgs.unstable (nixos-unstable), pkgs.unfree (this nixpkgs
# again) and pkgs.local, the packages in ../pkgs.
#
# No package set allows unfree licences wholesale. pkgs.unstable and
# pkgs.unfree each allow exactly the unfree packages listed below, by name, and
# the base set allows none; anything else unfree fails evaluation and has to be
# added here deliberately.
{
  nixpkgs,
  unstable,
}:
system:
let
  allowOnly = names: pkg: builtins.elem (nixpkgs.lib.getName pkg) names;

  unstablePkgs = import unstable {
    localSystem = system;
    config.allowUnfreePredicate = allowOnly [
      # modules/home/claude-code (both hosts)
      "claude-code"
      # modules/home/agent-harness: BUSL-1.1 since 1.0, see docs/agent-harness.md
      "rtk"
      # pkgs.local.granola (manwe)
      "granola"
      # modules/home/antigravity (manwe)
      "antigravity-hub"
      "antigravity-ide"
      "antigravity-cli"
      # manwe's home.packages in hosts/manwe
      "slack"
      "spotify"
      "vscode"
      "synology-drive-client"
    ];
  };
  unfreePkgs = import nixpkgs {
    localSystem = system;
    config.allowUnfreePredicate = allowOnly [
      # modules/nixos/onepassword, linux-desktop's autostart, users/david/nixos.nix
      "1password"
      "1password-cli"
      # modules/nixos/printing (Epson driver)
      "epson_201207w"
    ];
  };
  localpkgs = import ../pkgs { unstablePkgs = unstablePkgs; };
  overlay = final: prev: {
    unstable = unstablePkgs;
    unfree = unfreePkgs;
    local = localpkgs final prev;
  };
in
import nixpkgs {
  localSystem = system;
  overlays = [ overlay ];
}
