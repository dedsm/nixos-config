{hyprlandPkgs}: self: super: 
let
  pkgsPath = ./.;
in
{
  snyk-ls = super.callPackage ./snyk-ls { };

  cursor-appimage = super.callPackage ./cursor-appimage { };
}
