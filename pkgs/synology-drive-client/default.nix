{ stdenv
, lib
, qt5
, fetchurl
, autoPatchelfHook
, dpkg
, glibc
, gtk3
, pango
, libxcb
}:
let
  pname = "synology-drive-client";
  baseUrl = "https://global.synologydownload.com/download/Utility/SynologyDriveClient";
  version = "4.0.1-17885";
  buildNumber = "17885";
  meta = {
    description = "Desktop application to synchronize files and folders between the computer and the Synology Drive server";
    homepage = "https://www.synology.com/en-global/dsm/feature/drive";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [
      jcouyang
      MoritzBoehme
    ];
    platforms = [
      "x86_64-linux"
    ];
    mainProgram = "synology-drive";
  };

in
stdenv.mkDerivation {
  inherit
    pname
    version
    meta
    ;

  src = fetchurl {
    url = "${baseUrl}/${version}/Ubuntu/Installer/synology-drive-client-${buildNumber}.x86_64.deb";
    sha256 = "1j18baahvbfcsycwnrycgzgzb654rhk3a0179zb4jiilra3ymh8c";
  };

  nativeBuildInputs = [
    qt5.wrapQtAppsHook
    autoPatchelfHook
    dpkg
  ];

  buildInputs = [
    glibc
    gtk3
    pango
    libxcb
    qt5.qtdeclarative
    qt5.qtwayland
  ];

  unpackPhase = ''
    mkdir -p $out
    dpkg -x $src $out
    rm -rf $out/usr/lib/*/nautilus
    rm -rf $out/usr/lib/nautilus
    rm -rf $out/opt/Synology/SynologyDrive/package/cloudstation/icon-overlay
    rm -f $out/opt/Synology/SynologyDrive/package/cloudstation/lib/plugins/imageformats/libqpdf.so
  '';

  installPhase = ''
    cp -av $out/usr/* $out
    rm -rf $out/usr
    runHook postInstall
  '';

  postInstall = ''
    substituteInPlace $out/bin/synology-drive --replace /opt $out/opt
  '';
}
