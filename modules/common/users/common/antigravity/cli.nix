{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  glibc,
  versionInfo,
}:
let
  source =
    versionInfo.sources.${stdenv.hostPlatform.system}
      or (throw "antigravity-cli: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "antigravity-cli";
  inherit (versionInfo) version;

  src = fetchurl {
    inherit (source) url sha512;
  };

  sourceRoot = ".";

  strictDeps = true;
  __structuredAttrs = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    glibc
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 antigravity "$out/bin/antigravity"
    ln -s antigravity "$out/bin/agy"
    runHook postInstall
  '';

  meta = {
    description = "Google's agentic development platform CLI";
    homepage = "https://antigravity.google";
    license = lib.licenses.unfree;
    mainProgram = "antigravity";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-darwin"
      "x86_64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
