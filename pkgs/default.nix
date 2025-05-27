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

  cursor-appimage = let
    version = "0.50.5";
    pname = "cursor";

    src = super.fetchurl {
      url = "https://downloads.cursor.com/production/96e5b01ca25f8fbd4c4c10bc69b15f6228c80771/linux/x64/Cursor-0.50.5-x86_64.AppImage";
      name = "cursor-${version}.AppImage";
      sha256 = "sha256-DUWIgQYD3Wj6hF7NBb00OGRynKmXcFldWFUA6W8CZeM=";
    };

    appimageContents = super.appimageTools.extractType2 { 
      inherit pname version src;
    };
  in
    super.appimageTools.wrapType2 {
      inherit pname version src;

      extraInstallCommands = ''
        # Install the desktop file if it exists
        if [ -f ${appimageContents}/cursor.desktop ]; then
          install -Dm644 ${appimageContents}/cursor.desktop $out/share/applications/cursor.desktop
          substituteInPlace $out/share/applications/cursor.desktop \
            --replace 'Exec=AppRun' 'Exec=${pname} --no-sandbox'
        else
          # Create our own desktop file
          mkdir -p $out/share/applications
          cat > $out/share/applications/cursor.desktop << EOF
[Desktop Entry]
Name=Cursor
Comment=The AI Code Editor
Exec=${pname} --no-sandbox %F
Icon=cursor
Type=Application
Categories=Development;TextEditor;
StartupNotify=true
MimeType=text/plain;inode/directory;
EOF
        fi

        # Install icon if it exists, otherwise use a fallback
        if [ -f ${appimageContents}/cursor.png ]; then
          install -Dm644 ${appimageContents}/cursor.png $out/share/pixmaps/cursor.png
        elif [ -f ${appimageContents}/usr/share/icons/hicolor/256x256/apps/cursor.png ]; then
          install -Dm644 ${appimageContents}/usr/share/icons/hicolor/256x256/apps/cursor.png $out/share/pixmaps/cursor.png
        fi
      '';

      meta = with super.lib; {
        description = "The AI Code Editor";
        homepage = "https://cursor.com";
        downloadPage = "https://cursor.com/downloads";
        license = licenses.mit;
        sourceProvenance = with sourceTypes; [ binaryNativeCode ];
        maintainers = [ ];
        platforms = [ "x86_64-linux" ];
        mainProgram = "cursor";
      };
    };
}
