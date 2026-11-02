# Hex, local voice dictation, through the Home Manager module in its own flake
# (registered in modules/common). x86_64-linux only. See docs/hex.md.
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  cfg = config.dedsm.hex;

  transforms = pkgs.replaceVars ./hex.config.ts {
    port = toString osConfig.services.llama-cpp.port;
  };

  # A PipeWire source carrying whatever the default output plays. Passive, so
  # it doesn't keep the output awake. The low priority keeps WirePlumber from
  # picking it as the default microphone.
  speakersLoopback = pkgs.writeShellScript "hex-speakers-loopback" ''
    exec ${pkgs.pipewire}/bin/pw-loopback --name hex-speakers \
      --capture-props='stream.capture.sink=true node.passive=true' \
      --playback-props='media.class=Audio/Source node.name=hex_speakers node.description="Speakers (loopback)" priority.session=1 node.virtual=true'
  '';
in
{
  options.dedsm.hex = {
    enable = lib.mkEnableOption "Hex local voice dictation";
    cleanup.enable = lib.mkEnableOption "dictation cleanup through the local model server";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.cleanup.enable -> osConfig.dedsm.localLlm.enable;
        message = "dedsm.hex.cleanup needs dedsm.localLlm on the host.";
      }
    ];

    programs.hex = {
      enable = true;
      autostart = true;
      # English only, but Labs' live text needs a model that streams, and this
      # is the more accurate of the two that do. Parakeet v3 doesn't stream.
      model = "parakeet_unified_en";
      installModel = true;
      settings = {
        # foot pastes on Ctrl+Shift+V and sends Ctrl+V to the program inside.
        # Hex has one paste key for every app, so this applies everywhere.
        paste_with_shift = true;
        # Off, the mic stays open for the whole session, so an idle Hex holds
        # the audio device awake and keeps a Bluetooth headset on its call
        # profile.
        release_microphone_while_idle = true;
      }
      // lib.optionalAttrs cfg.cleanup.enable {
        # Spoken "open quote" and "new line", which the model would otherwise
        # leave as words, and the fillers it would have to spend time on.
        "labs.spoken_formatting" = true;
        "labs.filler_words" = true;
        # Replaces what the Output pane holds, so corrections belong here.
        "dictation_processing.default_mode" = {
          name = "Global";
          applications = [ ];
          browser_hosts = [ ];
          post_processing = {
            enabled = false;
            deadline_seconds = 30;
            model = null;
            variant = null;
            prompt = "Rewrite the transcript into clear, natural text while preserving the speaker's intended meaning.";
          };
          replacements = [ ];
          transformations = [ "cleanup" ];
        };
      };
    };

    # Copied, not linked: Hex's file watcher skips symlinks, so a linked config
    # wouldn't reload, and home.file would refuse Hex's own starter file. Only
    # when it differs, so a switch that changes nothing leaves it alone. Before
    # hexSettings, so the transform exists when the settings select it.
    home.activation.hexTransforms = lib.mkIf cfg.cleanup.enable (
      lib.hm.dag.entryBetween [ "hexSettings" ] [ "writeBoundary" ] ''
        target=${lib.escapeShellArg "${config.xdg.configHome}/hex/hex.config.ts"}
        if ! ${pkgs.diffutils}/bin/cmp -s ${transforms} "$target"; then
          run ${pkgs.coreutils}/bin/install -D -m 644 ${transforms} "$target"
        fi
      ''
    );

    # Hex's Microphone list holds ALSA devices only, so the PipeWire source
    # needs an ALSA device naming it before it can be picked there.
    systemd.user.services.hex-speakers-loopback = {
      Unit = {
        Description = "Speaker output as a source for Hex";
        After = [ "pipewire.service" ];
        BindsTo = [ "pipewire.service" ];
      };
      Service = {
        ExecStart = speakersLoopback;
        Restart = "on-failure";
        RestartSec = 5;
      };
      # default.target so a switch or login starts it, pipewire.service so it
      # comes back after BindsTo stops it on a PipeWire restart.
      Install.WantedBy = [
        "default.target"
        "pipewire.service"
      ];
    };
    home.file.".asoundrc".text = ''
      pcm.hex_speakers {
        type pipewire
        capture_node "hex_speakers"
        playback_node "-1"
        hint {
          show on
          description "Speakers (loopback)"
        }
      }
    '';

    # Hyprland's GlobalShortcuts portal takes Hex's shortcuts without a key, so
    # the key recorded in Hex's Settings does nothing here. Toggle rather than
    # hold, because a hold needs a release event and Lua binds drop it when the
    # modifier comes up first.
    wayland.windowManager.hyprland.extraConfig = ''
      -- Hex dictation (modules/home/hex)
      hl.bind("SUPER + D", hl.dsp.exec_cmd("hex dictation toggle"))
      hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd("hex paste-last"))
    '';
  };
}
