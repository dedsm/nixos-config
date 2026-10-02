{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs_22,
  caveman-bin,
  nix-update,
}:
# caveman CLI (`caveman claude`, `caveman trial`, ...): token compression for
# coding agents. The CLI is the published npm tarball, which bundles everything
# and has no runtime dependencies; the Go binaries it drives come from
# ./bin.nix and are pinned through `CAVEMAN_*_BIN`, so `caveman setup
# --install` has nothing to download. See docs/caveman.md.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "caveman";
  version = "2.0.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@caveman-ai/cli/-/cli-${finalAttrs.version}.tgz";
    hash = "sha512-B2y86nGKC+H2YxaPx+pug2mVTgB2CvccbcMez+RWQO/fPSbcSw0hUnM5SuFmrbrg5e+qklGbHyHEm6dgFUT9Og==";
  };

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # The CLI probes its binaries for the capabilities of the release it was
    # cut against, so a CLI bump without the matching `bin-v*` bump fails here
    # rather than at runtime.
    grep -q 'BINARY_RELEASE = "bin-v${caveman-bin.version}"' dist/binaries.generated.js || {
      echo "caveman ${finalAttrs.version} expects $(grep -o 'bin-v[0-9.]*' dist/binaries.generated.js), caveman-bin is ${caveman-bin.version}" >&2
      exit 1
    }

    lib=$out/lib/node_modules/@caveman-ai/cli
    mkdir -p $lib
    cp -r dist package.json $lib/

    # Telemetry is opt-out upstream (on by default in interactive shells);
    # `--set-default` keeps CAVEMAN_TELEMETRY=1 available as an explicit opt-in.
    makeWrapper ${lib.getExe nodejs_22} $out/bin/caveman \
      --add-flags $lib/dist/index.js \
      --set-default CAVEMAN_TELEMETRY 0 \
      ${lib.concatStringsSep " \\\n      " (
        lib.mapAttrsToList (envVar: binary: "--set-default ${envVar} ${caveman-bin}/bin/${binary}") {
          CAVEMAN_PROXY_BIN = "caveman-proxy";
          CAVEMAN_ENGINE_BIN = "caveman-engine";
          CAVEMAN_MCP_BIN = "caveman-mcp";
          CAVEMEM_BIN = "cavemem";
          CAVEMAN_SHRINK_BIN = "caveman-shrink";
          CAVEMAN_BROWSE_BIN = "caveman-browse";
        }
      )}
    ln -s caveman $out/bin/cave

    runHook postInstall
  '';

  passthru.updateScript = [
    (lib.getExe nix-update)
    "--flake"
    "caveman"
  ];

  meta = {
    description = "Recoverable context compression for coding agents";
    homepage = "https://github.com/JuliusBrussee/caveman";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
    mainProgram = "caveman";
  };
})
