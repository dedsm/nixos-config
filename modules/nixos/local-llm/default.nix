# A local OpenAI-compatible model server, for Hex and anything else on this
# machine. Requests name a model from models.json, which loads on demand and
# sleeps when idle. See docs/local-llm.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dedsm.localLlm;

  models = lib.importJSON ./models.json;

  # A file from the model's repo at its pinned commit.
  fetchFile =
    model: file: hash:
    pkgs.fetchurl {
      name = file;
      url = "https://huggingface.co/${model.repo}/resolve/${model.rev}/${file}";
      inherit hash;
    };

  modelFile = model: fetchFile model model.file model.hash;

  # The multimodal projector that lets a vision model read images, pinned to
  # the same commit as the model. Optional: a text-only model has none.
  mmprojPreset =
    model:
    lib.optionalAttrs (model ? mmproj) {
      mmproj = "${fetchFile model model.mmproj.file model.mmproj.hash}";
    };
in
{
  options.dedsm.localLlm.enable = lib.mkEnableOption "the local model server";

  config = lib.mkIf cfg.enable {
    services.llama-cpp = {
      enable = true;
      # The Vulkan build, for the iGPU. From unstable because that's the version
      # the router mode was tested on here.
      package = pkgs.unstable.llama-cpp-vulkan;
      # Loopback only: modules/nixos/core turns the firewall off.
      host = "127.0.0.1";
      # Not the module's 8080, which development servers tend to want.
      port = 8012;
      modelsPreset = lib.mapAttrs (
        _: model: model.preset // { model = "${modelFile model}"; } // mmprojPreset model
      ) models;
      extraFlags = [
        "--models-max"
        "2"
        # Frees a model after 4 hours unused. Long, because the first request
        # after that waits for the load, which is 4 s for a 5 GB model.
        "--sleep-idle-seconds"
        "14400"
      ];
    };

    systemd.services.llama-cpp.environment = {
      # The router fails to start if it can't check for a Hugging Face cache
      # under $HOME. This is the module's StateDirectory.
      HOME = "/var/lib/llama-cpp";
      # Mesa's shader cache, in the module's CacheDirectory.
      XDG_CACHE_HOME = "/var/cache/llama-cpp";
    };
  };
}
