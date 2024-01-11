{ hyprlandPkgs }:
self: super: {
  hyprland-grab-workspace = super.gcc13Stdenv.mkDerivation {
    name = "hyprland-grab-workspace";
    src = super.fetchFromGitHub {
      owner = "CMurtagh-LGTM";
      repo = "grab-workspace";
      rev = "51cd5d1cc39385988db5f65e94ff4177f22dc9fb";
      sha256 = "sha256-0QzmZdGnoVWyTO1ayYYW8vEVZyl7O70Mi/Hu6/+HWHA=";
    };

    #inherit (super.hyprland) nativeBuildInputs;
    nativeBuildInputs = with super; [
      jq
      makeWrapper
      pkg-config
      wayland-scanner
    ];

    buildInputs = [ hyprlandPkgs.packages.${super.system}.hyprland ]
      ++ hyprlandPkgs.packages.${super.system}.hyprland.buildInputs;

    installPhase = ''
      mkdir -p $out/lib
      cp grab-workspace.so $out/lib
    '';
  };
}
