{ lib
, fetchurl
, appimageTools
, makeWrapper
}:

let
  pname = "cursor";
  version = "1.5.5";

  src = fetchurl {
    url = "https://downloads.cursor.com/production/823f58d4f60b795a6aefb9955933f3a2f0331d7b/linux/x64/Cursor-1.5.5-x86_64.AppImage";
    name = "cursor-${version}.AppImage";
    sha256 = "sha256-eq/AQcAONs6HBpRdx2yf4MFTQ1cm/rOeaZZTq8YUF8s=";
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

      # Find and install all desktop files
      find "${contents}" -name "*.desktop" -print0 | while IFS= read -r -d $'\0' f; do
        if [ ! -e "$f" ]; then continue; fi

        local desktop_file_name=$(basename "$f")
        install -m 444 -D "$f" "$out/share/applications/$desktop_file_name"

        # Replace the executable in all Exec= lines with our wrapped binary,
        # preserving any arguments.
        sed -i -E "s/^(Exec=)[^ ]+/\1${pname}/" "$out/share/applications/$desktop_file_name"
      done

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
