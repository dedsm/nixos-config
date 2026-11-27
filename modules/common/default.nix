# Shared by both host builders: system fonts, the nix registry, and the
# Home Manager settings every user gets. The users themselves are set by the
# builders (home-manager.users); every module in modules/home is registered for
# all of them here and stays off until a user's config enables it.
{
  self,
  nixpkgs,
  unstable,
  hyprdynamicmonitors,
  hex,
  ...
}:
{
  imports = [ ./fonts.nix ];

  nix.registry = {
    nixpkgs.flake = nixpkgs;
    unstable.flake = unstable;
  };

  # Home Manager evaluates with the system's pkgs, overlays included
  # (pkgs.local, .unstable, .unfree), instead of importing its own.
  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "home_manager_bak";
  # hyprland/hyprdynamicmonitors takes the daemon's package from the input.
  # self and nixpkgs give a module a clock for an expiring workaround: pure
  # evaluation has none, so "now" is max of their lastModified (herdr's).
  home-manager.extraSpecialArgs = {
    inherit
      hex
      hyprdynamicmonitors
      self
      nixpkgs
      ;
  };
  home-manager.sharedModules = [
    ../home
    hyprdynamicmonitors.homeManagerModules.default
    hex.homeManagerModules.default
  ];
}
