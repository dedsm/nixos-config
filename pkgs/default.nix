{ hyprlandPkgs, unstablePkgs }: self: super: 
let
  pkgsPath = ./.;
in
{
  snyk-ls = super.callPackage ./snyk-ls { };

  cursor-appimage = super.callPackage ./cursor-appimage { };

  slack = super.callPackage ./slack { slack = unstablePkgs.slack; };

  cli-notify = super.callPackage ./cli-notify { };

  headroom = super.callPackage ./headroom { };
}
