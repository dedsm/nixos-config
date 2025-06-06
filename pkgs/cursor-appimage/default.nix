{ lib
, fetchurl
, appimageTools
, makeWrapper
}:

let
  pname = "cursor";
  version = "1.0.0";

  src = fetchurl {
    url = "https://downloads.cursor.com/production/53b99ce608cba35127ae3a050c1738a959750865/linux/x64/Cursor-1.0.0-x86_64.AppImage";
    name = "cursor-${version}.AppImage";
    sha256 = "sha256-HJiT3aDB66K2slcGJDC21+WhK/kv4KCKVZgupbfmLG0=";
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands =
    let
      contents = appimageTools.extract { inherit pname version src; };
    in
    ''
      wrapProgram $out/bin/${pname} \
        --add-flags "--no-sandbox" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

      # Install the desktop file if it exists
      if [ -f ${contents}/${pname}.desktop ]; then
        install -m 444 -D ${contents}/${pname}.desktop -t $out/share/applications
        substituteInPlace $out/share/applications/${pname}.desktop \
          --replace-warn 'Exec=AppRun' 'Exec=${pname}'
      else
        # Create our own desktop file
        mkdir -p $out/share/applications
        cat > $out/share/applications/${pname}.desktop << EOF
[Desktop Entry]
Name=Cursor
Comment=The AI Code Editor
Exec=${pname} %F
Icon=cursor
Type=Application
Categories=Development;TextEditor;
StartupNotify=true
MimeType=text/plain;inode/directory;
EOF
      fi

      # Install icons
      if [ -d ${contents}/usr/share/icons ]; then
        cp -r ${contents}/usr/share/icons $out/share
      elif [ -f ${contents}/cursor.png ]; then
        install -m 444 -D ${contents}/cursor.png $out/share/pixmaps/cursor.png
      elif [ -f ${contents}/usr/share/icons/hicolor/256x256/apps/cursor.png ]; then
        install -m 444 -D ${contents}/usr/share/icons/hicolor/256x256/apps/cursor.png $out/share/pixmaps/cursor.png
      fi
    '';

  meta = with lib; {
    description = "The AI Code Editor";
    homepage = "https://cursor.com";
    downloadPage = "https://cursor.com/downloads";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "cursor";
  };
} 
