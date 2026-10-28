# The package set every host and flake output is built from: nixpkgs plus one
# overlay adding pkgs.unstable and pkgs.unfree (both with allowUnfree) and
# pkgs.local, the packages in ../pkgs.
{
  nixpkgs,
  unstable,
  antigravity-nix,
}:
system:
let
  unstablePkgs = import unstable {
    localSystem = system;
    config = {
      allowUnfree = true;
    };
  };
  unfreePkgs = import nixpkgs {
    localSystem = system;
    config = {
      allowUnfree = true;
    };
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
