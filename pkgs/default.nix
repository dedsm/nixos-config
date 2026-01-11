{ hyprlandPkgs, unstablePkgs }: self: super: 
let
  pkgsPath = ./.;
in
{
  snyk-ls = super.callPackage ./snyk-ls { };

  cursor-appimage = super.callPackage ./cursor-appimage { };

  slack = super.callPackage ./slack { slack = unstablePkgs.slack; };

  synology-drive-client = super.callPackage ./synology-drive-client { };
}
