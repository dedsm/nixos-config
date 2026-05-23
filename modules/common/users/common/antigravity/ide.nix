{
  lib,
  stdenv,
  buildVscode,
  fetchurl,
  writeShellScript,
  coreutils,
  versionInfo,
  commandLineArgs ? "",
  useVSCodeRipgrep ? stdenv.hostPlatform.isDarwin,
}:

let
  inherit (stdenv) hostPlatform;
  source =
    versionInfo.sources.${hostPlatform.system}
      or (throw "antigravity-ide: unsupported system ${hostPlatform.system}");
in
buildVscode {
  inherit commandLineArgs useVSCodeRipgrep;
  inherit (versionInfo) version vscodeVersion;
  pname = "antigravity-ide";

  executableName = "antigravity-ide";
  longName = "Antigravity IDE";
  shortName = "Antigravity IDE";
  libraryName = "antigravity-ide";
  iconName = "antigravity-ide";

  src = fetchurl { inherit (source) url sha256; };

  sourceRoot = if hostPlatform.isDarwin then "Antigravity IDE.app" else "Antigravity IDE";

  tests = { };

  updateScript = writeShellScript "antigravity-ide-update-noop" ''
    echo "Run scripts/update-antigravity.sh in this repo to refresh version.json" >&2
    exit 1
  '';

  customizeFHSEnv =
    args:
    args
    // {
      extraBwrapArgs = (args.extraBwrapArgs or [ ]) ++ [ "--tmpfs /opt/google/chrome" ];
      extraBuildCommands = (args.extraBuildCommands or "") + ''
        mkdir -p "$out/opt/google/chrome"
      '';
      runScript = writeShellScript "antigravity-ide-wrapper" ''
        for candidate in google-chrome-stable google-chrome chromium-browser chromium; do
          if target=$(command -v "$candidate"); then
            ${coreutils}/bin/ln -sf "$target" /opt/google/chrome/chrome
            break
          fi
        done
        exec ${args.runScript} "$@"
      '';
    };

  meta = {
    mainProgram = "antigravity-ide";
    description = "Agentic development platform, evolving the IDE into the agent-first era";
    homepage = "https://antigravity.google/product/antigravity-ide";
    downloadPage = "https://antigravity.google/download#antigravity-ide";
    changelog = "https://antigravity.google/changelog";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
