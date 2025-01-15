{hyprlandPkgs}: self: super: {
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
