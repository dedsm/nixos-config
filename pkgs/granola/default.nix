{
  lib,
  stdenv,
  fetchurl,
  unzip,
  asar,
  nodejs,
  node-gyp,
  python3,
  autoPatchelfHook,
  patchelfUnstable,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  electron,
  writeShellApplication,
  curl,
  jq,
  yq-go,
  gnugrep,
  gnused,
}:
# Granola only ships for macOS and Windows, but it is an Electron app: the
# macOS build carries all of its JavaScript, which runs fine on nixpkgs'
# Electron once three things are fixed (platform label, resourcesPath, and the
# patched SQLite native module). This is the recipe from
# https://github.com/tirtha4/Granola-for-Linux, done as a derivation.
# See docs/granola.md.
let
  # Granola bundles a *patched fork* of better-sqlite3-multiple-ciphers (it adds
  # the `updateHook()` the renderer calls on startup) with its full C++ source
  # but without binding.gyp. The build file comes from the matching npm release;
  # the sources stay Granola's. The build checks the two versions agree.
  sqliteCipher = rec {
    version = "12.9.0";
    src = fetchurl {
      url = "https://registry.npmjs.org/better-sqlite3-multiple-ciphers/-/better-sqlite3-multiple-ciphers-${version}.tgz";
      hash = "sha512-471izuwJKCgvCGJ0VP10Z0IN7NWFW+pk/A8KXItZXVJ0V2AEAB5HZfmc9U3VLMmJ46bRaPbdgaBbgWpBJ/biUg==";
    };
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "granola";
  version = "7.626.1";

  # The macOS auto-update payload, which is what the in-app updater installs: a
  # versioned universal .zip (the .dmg on the website is LZFSE-compressed APFS,
  # which needs a recent 7zz). The hash is the feed's own sha512.
  src = fetchurl {
    url = "https://dr2v7l5emb758.cloudfront.net/${finalAttrs.version}/Granola-${finalAttrs.version}-mac-universal.zip";
    hash = "sha512-hlx09Bi+uGoudeHI8ouaylGgXWQZhQLncWBNhNrMzJsPsMkyoVdibhZ25ffJqucdK28wnzm0mmGCvqZW9k3+Uw==";
  };

  nativeBuildInputs = [
    unzip
    asar
    nodejs
    python3
    autoPatchelfHook
    # stdenv's patchelf (0.15) corrupts drag.node: it segfaults in its own
    # initializers on dlopen. As in firefox-bin/floorp-bin, the newer one
    # takes precedence for autoPatchelfHook.
    patchelfUnstable
    makeWrapper
    copyDesktopItems
  ];

  # The prebuilt linux-x64 drag.node from electron-click-drag-plugin, which the
  # main process requires at startup, links libstdc++/libgcc_s.
  buildInputs = [ (lib.getLib stdenv.cc.cc) ];

  # Only the JS payload, its icons and Electron's Info.plist (for the version
  # check); the rest of the 300 MB bundle is the macOS Electron runtime and
  # Mach-O helpers.
  unpackPhase = ''
    runHook preUnpack
    unzip -q $src \
      'Granola.app/Contents/Frameworks/Electron Framework.framework/Versions/A/Resources/Info.plist' \
      'Granola.app/Contents/Resources/app.asar' \
      'Granola.app/Contents/Resources/app.asar.unpacked/*' \
      'Granola.app/Contents/Resources/icons/*'
    runHook postUnpack
  '';

  sourceRoot = "Granola.app/Contents";

  buildPhase = ''
    runHook preBuild

    # The native module is built against Electron's ABI, which only holds
    # within a major version.
    bundledElectron=$(grep -A1 CFBundleVersion \
      'Frameworks/Electron Framework.framework/Versions/A/Resources/Info.plist' \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    if [ "''${bundledElectron%%.*}" != "${lib.versions.major electron.version}" ]; then
      echo "Granola ${finalAttrs.version} ships Electron $bundledElectron, but this builds it against electron ${electron.version}." >&2
      echo "Switch the granola entry in pkgs/default.nix to electron_''${bundledElectron%%.*}." >&2
      exit 1
    fi

    # Run from a plain directory rather than the asar: the patches below are
    # ordinary text edits, and `asar extract` folds app.asar.unpacked back in.
    asar extract Resources/app.asar app

    # api.granola.ai answers 500 to any request with platform=linux, sign-in
    # included. The app maps darwin->macOS and win32->Windows and passes
    # anything else through, so rewrite that fallback to report Windows. Only
    # the label sent to the API changes; process.platform stays linux.
    platformFallback='\?`Windows`:(window\.electron|process)\.platform([^=.[:alnum:]_]|$)'
    patched=$( (grep -rhoE "$platformFallback" app/dist-app app/dist-electron || true) | wc -l)
    if [ "$patched" -eq 0 ]; then
      echo "No platform fallback found to patch; Granola's bundler output has changed." >&2
      exit 1
    fi
    grep -rlE "$platformFallback" app/dist-app app/dist-electron \
      | xargs sed -i -E "s/$platformFallback/?\`Windows\`:\`Windows\`\2/g"
    echo "rewrote $patched platform fallback(s)"

    # The wrapper sets ELECTRON_FORCE_IS_PACKAGED, without which the app runs in
    # its dev mode (granola-dev:// sign-in callback, remote debugging port,
    # mock keychain). Packaged mode resolves icons and helpers through
    # process.resourcesPath, which would be nixpkgs' Electron's own directory,
    # so point it at ours.
    resourcesUsers=$(grep -rlF process.resourcesPath app/dist-electron || true)
    if [ -z "$resourcesUsers" ]; then
      echo "process.resourcesPath no longer appears in dist-electron; recheck the resources patch." >&2
      exit 1
    fi
    for f in $resourcesUsers; do
      substituteInPlace "$f" --replace-fail process.resourcesPath "\"$out/share/granola/resources\""
    done

    # Rebuild Granola's SQLite fork from its own sources for Linux.
    bs3=app/node_modules/better-sqlite3-multiple-ciphers
    bundledSqlite=$(node -p "require('./$bs3/package.json').version")
    if [ "$bundledSqlite" != "${sqliteCipher.version}" ]; then
      echo "Granola bundles better-sqlite3-multiple-ciphers $bundledSqlite, but binding.gyp is pinned from ${sqliteCipher.version}." >&2
      echo "Run scripts/update-packages.sh granola." >&2
      exit 1
    fi
    tar xzf ${sqliteCipher.src} package/binding.gyp
    cp package/binding.gyp $bs3/
    # nixpkgs' node-gyp wrapper force-sets npm_config_nodedir to its own
    # nodejs, overriding the usual `npm_config_nodedir=''${electron.headers}`
    # (and --nodedir). Node's headers ship a stock sqlite3.h that shadows the
    # cipher-enabled one, and the ABI would be Node's rather than Electron's,
    # so call node-gyp's entry point directly.
    (
      cd $bs3
      export HOME=$TMPDIR npm_config_nodedir=${electron.headers}
      node ${node-gyp}/lib/node_modules/node-gyp/bin/node-gyp.js rebuild --release --jobs $NIX_BUILD_CORES
    )
    # Keep only the built modules; the sources and objects are dead weight.
    find $bs3/build -mindepth 1 -maxdepth 1 ! -name Release -exec rm -rf {} +
    find $bs3/build/Release -mindepth 1 -maxdepth 1 ! -name '*.node' -exec rm -rf {} +
    rm -rf $bs3/src $bs3/deps $bs3/binding.gyp

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/granola/resources
    cp -r app Resources/icons $out/share/granola/resources/
    install -Dm644 Resources/icons/icon.png $out/share/pixmaps/granola.png

    # Same Wayland flags as pkgs/slack: an explicit --ozone-platform rather than
    # nixpkgs' `auto` hint, under nixpkgs' usual NIXOS_OZONE_WL gate.
    makeWrapper ${lib.getExe electron} $out/bin/granola \
      --add-flags $out/share/granola/resources/app \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --set ELECTRON_FORCE_IS_PACKAGED 1

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "granola";
      desktopName = "Granola";
      comment = "AI notepad for meetings";
      exec = "granola %U";
      icon = "granola";
      categories = [
        "Office"
        "Utility"
      ];
      # Sign-in comes back through granola:// links.
      mimeTypes = [ "x-scheme-handler/granola" ];
      startupWMClass = "granola";
    })
  ];

  # Upstream's smoke test: the main process loads these at startup, and the
  # renderer's cache layer needs an encrypted database with a working
  # updateHook(). A stock better-sqlite3 build fails the last check.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ELECTRON_RUN_AS_NODE=1 ${lib.getExe electron} -e "
      const modules = '$out/share/granola/resources/app/node_modules';
      require(modules + '/electron-click-drag-plugin');
      require(modules + '/registry-js');
      const Database = require(modules + '/better-sqlite3-multiple-ciphers');
      const db = new Database('$TMPDIR/smoke.db');
      db.pragma(\"cipher='sqlcipher'\");
      db.pragma(\"key='smoketest'\");
      db.exec('CREATE TABLE t(a)');
      let fired = false;
      db.updateHook(() => { fired = true; });
      db.prepare('INSERT INTO t VALUES (1)').run();
      if (db.prepare('SELECT count(*) c FROM t').get().c !== 1) throw new Error('insert failed');
      if (!fired) throw new Error('updateHook did not fire');
      db.close();
    "
    runHook postInstallCheck
  '';

  passthru = {
    inherit electron sqliteCipher;
    updateScript = [
      (lib.getExe (writeShellApplication {
        name = "update-granola";
        runtimeInputs = [
          curl
          jq
          yq-go
          unzip
          gnugrep
          gnused
        ];
        text = builtins.readFile ./update.sh;
      }))
    ];
  };

  meta = {
    description = "AI notepad for meetings, repackaged from the macOS build";
    homepage = "https://www.granola.ai";
    license = lib.licenses.unfree;
    # Minified JS plus electron-click-drag-plugin's prebuilt drag.node.
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    # drag.node is only prebuilt for x86_64 Linux.
    platforms = [ "x86_64-linux" ];
    mainProgram = "granola";
  };
})
