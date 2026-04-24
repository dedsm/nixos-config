{ lib, homeManagerConfig, pkgs, ... }:
let
  cfg = homeManagerConfig.gemini-cli or {};
  enable = cfg.enable or false;
  isDarwin = pkgs.stdenv.isDarwin;

  jq = "${pkgs.jq}/bin/jq";
  cat = "${pkgs.coreutils}/bin/cat";
  mv = "${pkgs.coreutils}/bin/mv";
  cp = "${pkgs.coreutils}/bin/cp";
  mkdir = "${pkgs.coreutils}/bin/mkdir";

  notifyScriptDefault = import ./notify.nix { inherit pkgs isDarwin; };
  notifyScript = cfg.notifyScript or notifyScriptDefault;

  # === Managed Settings ===
  managedSettings = {
    ui = {
      # DevEx: Dynamic window title shows agent state (thinking, running tool, idle) in the terminal tab
      dynamicWindowTitle = true;
      # DevEx: Showing status in title removes visual clutter from the primary chat flow
      showStatusInTitle = true;
      footer = {
        hideSandboxStatus = true;
      };
      # Auto theme switching config
      autoThemeSwitching = true;
    };
    hooksConfig = {
      # DevEx: AfterAgent hooks run when the model completes its task.
      # We hook in a notification script so you can background long-running tasks
      AfterAgent = [{
        command = "~/.local/bin/notify-gemini.sh";
        sequential = false;
      }];
    };
  } // (cfg.extraSettings or {});

  managedSettingsFile = pkgs.writeText "gemini-managed-settings.json" (builtins.toJSON managedSettings);

  mergeScript = pkgs.writeShellScript "merge-gemini-settings" ''
    SETTINGS="$HOME/.gemini/settings.json"
    ${mkdir} -p "$HOME/.gemini"
    if [ -f "$SETTINGS" ] && ${jq} empty "$SETTINGS" 2>/dev/null; then
      ${jq} -s '.[0] * .[1]' "$SETTINGS" ${managedSettingsFile} > "$SETTINGS.tmp" && ${mv} "$SETTINGS.tmp" "$SETTINGS"
    else
      ${cp} ${managedSettingsFile} "$SETTINGS"
    fi
  '';

in
lib.mkIf enable {
  home.packages =
    [ pkgs.unstable.gemini-cli ]
    ++ lib.optionals (!isDarwin) [ pkgs.libnotify ];

  home.file.".local/bin/notify-gemini.sh" = {
    executable = true;
    text = notifyScript;
  };

  home.activation.mergeGeminiSettings = {
    after = ["writeBoundary"];
    before = [];
    data = ''
      $DRY_RUN_CMD ${mergeScript}
    '';
  };
}
