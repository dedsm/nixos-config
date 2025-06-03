{ lib
, buildGoModule
, fetchFromGitHub
}:

let
  version = "20241112.105448";
in
buildGoModule {
  pname = "snyk-ls";
  inherit version;

  src = fetchFromGitHub {
    owner = "snyk";
    repo = "snyk-ls";
    rev = "v${version}";
    sha256 = "sha256-unNyaY9lT/0t80fsjBfwos9Jr1ylQVDvKrPK01BuIao=";
  };

  buildPhase = ''
    go build -o $out/bin/snyk-ls
  '';

  vendorHash = "sha256-aiYFmGmcY/qOCMELhSaKS2TA7QBLyZ4+GTbKgF7hOkg=";

  meta = with lib; {
    description = "Snyk Language Server";
    homepage = "https://github.com/snyk/snyk-ls";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = platforms.linux;
  };
} 