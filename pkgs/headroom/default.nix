# Headroom — local context-compression proxy / MCP server for AI coding agents.
#
# Installed from the prebuilt PyPI abi3 wheel (one wheel covers Python >= 3.10),
# pinned per-platform in ./version.json — run scripts/update-headroom.sh to bump.
# This trades the from-source maturin build for speed + low maintenance; the
# trade-offs vs a source build:
#   * The wheel's Rust core fetches the ONNX Runtime at runtime (cdn.pyke.io) and
#     ignores ORT_DYLIB_PATH, so we cannot point it at nixpkgs `onnxruntime`. On
#     NixOS that downloaded .so may need `programs.nix-ld.enable = true` for the
#     ONNX-backed features (relevance / Kompress); SmartCrusher + the proxy work
#     regardless. The python `onnxruntime` below (nixpkgs, patchelf-clean) covers
#     the python text-compression path.
#   * `ast-grep` is provided on PATH (headroom's `binaries.resolve()` honors it);
#     the existing `pkgs.unstable.rtk` is found the same way, so it is not bundled.
{
  lib,
  python3,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  ast-grep,
  makeWrapper,
}:
let
  pin = lib.importJSON ./version.json;
  plat =
    pin.platforms.${stdenv.hostPlatform.system}
      or (throw "headroom: no wheel pinned for ${stdenv.hostPlatform.system}");
in
python3.pkgs.buildPythonApplication {
  pname = "headroom-ai";
  version = pin.version;
  format = "wheel";

  src = fetchurl { inherit (plat) url sha256; };

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  # The wheel's bundled native extension (.so) needs libstdc++/libgcc on Linux.
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  # Curated runtime extras for the Claude-Code use case: [proxy] web stack + MCP
  # server + ONNX text compression (Kompress) + lightweight memory (sqlite-vec /
  # hnswlib, ONNX embedder — no torch). `ast-grep-cli` is dropped (not in nixpkgs;
  # the `ast-grep` binary is on PATH instead). Heavier extras ([ml]/torch, [code]
  # tree-sitter, [image]) are intentionally omitted — append here to add them.
  dependencies =
    (with python3.pkgs; [
      # core
      click
      litellm
      opentelemetry-api
      pydantic
      rich
      tiktoken
      # proxy
      fastapi
      h2
      httpx
      uvicorn
      mcp
      onnxruntime # python binding for Kompress INT8 text compression
      transformers # Kompress tokenizer
      # memory (ONNX embedder path — no torch)
      sqlite-vec
      hnswlib
    ])
    ++ lib.optionals (lib.versionOlder python3.pythonVersion "3.11") [ python3.pkgs.tomli ];

  # nixpkgs ships versions slightly outside headroom's declared floors/caps; all
  # are lazily imported and behaviour-compatible for the proxy path.
  pythonRelaxDeps = [
    "litellm"
    "transformers"
  ];
  pythonRemoveDeps = [ "ast-grep-cli" ];

  pythonImportsCheck = [ "headroom" ];

  makeWrapperArgs = [
    "--suffix PATH : ${lib.makeBinPath [ ast-grep ]}"
    "--set-default HEADROOM_TELEMETRY off"
    "--set-default HEADROOM_UPDATE_CHECK off"
  ];

  meta = {
    description = "Context compression layer for LLM agents — 60-95% fewer tokens (proxy/MCP/library)";
    homepage = "https://github.com/chopratejas/headroom";
    changelog = "https://github.com/chopratejas/headroom/blob/v${pin.version}/CHANGELOG.md";
    license = lib.licenses.asl20;
    mainProgram = "headroom";
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
