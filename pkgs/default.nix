{hyprlandPkgs}: self: super: {
  fw-fanctrl-nix = super.stdenv.mkDerivation {
    name = "fw-fanctrl-nix";
    src = super.fetchFromGitHub {
      owner = "TamtamHero";
      repo = "fw-fanctrl";
      rev = "fb4c933e8eb1f362979cad8455297a7c6e6d2efa";
      sha256 = "sha256-UDGadPeNn/ouQ9Rtg8Wzc5QvG15TkN5+LhRwyX86l1o=";
    };
    propagatedBuildInputs = [super.python311Packages.watchdog];
    nativeBuildInputs = with super; [jq makeWrapper pkg-config];

    installPhase = ''
      mkdir -p $out/bin
      cp fanctrl.py $out/bin/fw-fanctrl
      chmod +x $out/bin/fw-fanctrl
      mkdir -p $out/config
      cp ${./fanctrl-config.json} $out/config/config.json
    '';
  };

  snyk-ls = let
    version = "20241112.105448";
  in
    super.buildGoModule {
      pname = "snyk-ls";
      inherit version;

      src = super.fetchFromGitHub {
        owner = "snyk";
        repo = "snyk-ls";
        rev = "v${version}";
        sha256 = "sha256-unNyaY9lT/0t80fsjBfwos9Jr1ylQVDvKrPK01BuIao=";
      };

      buildPhase = ''
        go build -o $out/bin/snyk-ls
      '';

      vendorHash = "sha256-aiYFmGmcY/qOCMELhSaKS2TA7QBLyZ4+GTbKgF7hOkg=";

      meta = {
        description = "Snyk Language Server";
        homepage = "https://github.com/snyk/snyk-ls";
      };
    };
}
