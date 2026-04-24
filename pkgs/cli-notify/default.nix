{ lib, stdenv, swift, darwin }:

stdenv.mkDerivation {
  pname = "cli-notify";
  version = "1.0";

  src = ./.;

  nativeBuildInputs = [ swift darwin.sigtool ];

  buildPhase = ''
    runHook preBuild

    mkdir -p build
    swiftc \
      -O \
      -framework UserNotifications \
      -framework Foundation \
      Notify.swift \
      -o build/cli-notify

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    APP_DIR="$out/Applications/CLINotify.app"
    mkdir -p "$APP_DIR/Contents/MacOS"
    cp Info.plist "$APP_DIR/Contents/Info.plist"
    cp build/cli-notify "$APP_DIR/Contents/MacOS/cli-notify"

    # Ad-hoc sign the binary so macOS UNUserNotifications will accept it.
    # sigtool only signs Mach-O files, not the bundle directory.
    codesign --force --sign - "$APP_DIR/Contents/MacOS/cli-notify"

    mkdir -p "$out/bin"
    ln -s "$APP_DIR/Contents/MacOS/cli-notify" "$out/bin/cli-notify"

    runHook postInstall
  '';

  meta = {
    description = "Minimal macOS UNUserNotifications CLI with identifier-based replacement";
    platforms = lib.platforms.darwin;
  };
}
