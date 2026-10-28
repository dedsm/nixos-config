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
  antigravity-nix,
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
      # pkgs.local.slack and pkgs.local.granola (manwe)
      "slack"
      "granola"
      # pkgs.local.antigravity-{hub,ide,cli}, via modules/home/antigravity (manwe);
      # the GUI packages depend on google-chrome, see docs/antigravity.md
      "google-antigravity2"
      "google-antigravity-ide"
      "google-antigravity-cli"
      "google-chrome"
      # manwe's home.packages in hosts/manwe
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
  localpkgs = import ../pkgs {
    unstablePkgs = unstablePkgs;
    antigravityNix = antigravity-nix;
  };
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
