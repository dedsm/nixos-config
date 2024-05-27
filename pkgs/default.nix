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

  fw-fanctrl-nix = super.stdenv.mkDerivation {
    name = "fw-fanctrl-nix";
    src = super.fetchFromGitHub {
      owner = "TamtamHero";
      repo = "fw-fanctrl";
      rev = "fb4c933e8eb1f362979cad8455297a7c6e6d2efa";
      sha256 = "sha256-UDGadPeNn/ouQ9Rtg8Wzc5QvG15TkN5+LhRwyX86l1o=";
    };
    propagatedBuildInputs = [ super.python311Packages.watchdog ];
    nativeBuildInputs = with super; [ jq makeWrapper pkg-config ];

    installPhase = ''
      mkdir -p $out/bin
      cp fanctrl.py $out/bin/fw-fanctrl
      chmod +x $out/bin/fw-fanctrl
      mkdir -p $out/config
      cp ${./fanctrl-config.json} $out/config/config.json
    '';
  };
}
