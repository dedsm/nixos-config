# Hex, local voice dictation, through the Home Manager module in its own flake
# (registered in modules/common). x86_64-linux only. See docs/hex.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dedsm.hex;

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
  options.dedsm.hex.enable = lib.mkEnableOption "Hex local voice dictation";

  config = lib.mkIf cfg.enable {
    programs.hex = {
      enable = true;
      autostart = true;
      # Parakeet v3 rather than Hex's English-only default: 25 languages,
      # detected from the audio.
      model = "parakeet_v3";
      installModel = true;
      settings = {
        # foot pastes on Ctrl+Shift+V and sends Ctrl+V to the program inside.
        # Hex has one paste key for every app, so this applies everywhere.
        paste_with_shift = true;
        # Off, the mic stays open for the whole session, so an idle Hex holds
        # the audio device awake and keeps a Bluetooth headset on its call
        # profile.
        release_microphone_while_idle = true;
      };
    };

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
