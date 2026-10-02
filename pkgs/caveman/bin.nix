{
  lib,
  buildGoModule,
  fetchFromGitHub,
  nix-update,
}:
# The Go half of caveman: the local proxy, the compression engine, the recovery
# MCP server, the memory store, the tool-catalog shrinker and the browser
# bridge — the same set as upstream's RELEASE_BINARIES. Upstream ships
# these as signed release binaries that `caveman setup --install` downloads into
# ~/.caveman/bin at runtime; building them here keeps them in the store instead.
#
# Same build as upstream's scripts/build-release-binaries.mjs: plain
# `go build -trimpath` with CGO off (SQLite is modernc.org/sqlite, pure Go), so
# the result is static and needs no patching on NixOS.
buildGoModule (finalAttrs: {
  pname = "caveman-bin";
  version = "2.0.0";

  src = fetchFromGitHub {
    owner = "JuliusBrussee";
    repo = "caveman";
    tag = "bin-v${finalAttrs.version}";
    hash = "sha256-XtrZSxw1Hv2+YAm+zMZSBY4uumLDSsRR0LgYwd6jKlg=";
  };

  vendorHash = "sha256-aL0B0t+MUyg/+qrMeLSCK/g4H6MsFrYH10Uf9f4nWOg=";

  subPackages = [
    "proxy/cmd/caveman-proxy"
    "engine/cmd/caveman-engine"
    "mcp/cmd/caveman-mcp"
    "mem/cmd/cavemem"
    "shrink/cmd/caveman-shrink"
    "browse/cmd/caveman-browse"
  ];

  env.CGO_ENABLED = 0;

  # Asserts that `status` trusts a live listener by inspecting the test process
  # itself (name + liveness), which the build sandbox does not expose.
  checkFlags = [ "-skip=^TestRunStatusRequiresThisListenerGeneration$" ];

  # Upstream tags each component separately; the binaries are the `bin-v*` tags.
  passthru.updateScript = [
    (lib.getExe nix-update)
    "--flake"
    "--version-regex"
    "bin-v(.*)"
    "caveman-bin"
  ];

  meta = {
    description = "Local proxy, engine and MCP binaries for the caveman CLI";
    homepage = "https://github.com/JuliusBrussee/caveman";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
    mainProgram = "caveman-proxy";
  };
})
