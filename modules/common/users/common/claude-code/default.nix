{ lib, homeManagerConfig, pkgs, ... }:
let
  cfg = homeManagerConfig.claude-code or {};
  enable = cfg.enable or false;
  isDarwin = pkgs.stdenv.isDarwin;

  # Nix store paths for commands used only in this file
  jq = "${pkgs.jq}/bin/jq";
  mv = "${pkgs.coreutils}/bin/mv";
  cp = "${pkgs.coreutils}/bin/cp";
  mkdir = "${pkgs.coreutils}/bin/mkdir";

  # Import script modules
  fileSuggestionScript = import ./file-suggestion.nix { inherit pkgs; };
  notifyScriptDefault = import ./notify.nix { inherit pkgs isDarwin; };
  dismissScriptDefault = import ./dismiss.nix { inherit pkgs isDarwin; };
  statusLineScript = import ./statusline.nix { inherit pkgs; };

  notifyScript = cfg.notifyScript or notifyScriptDefault;
  dismissScript = cfg.dismissScript or dismissScriptDefault;

  # === Managed Settings ===
  managedSettings = {
    fileSuggestion = {
      type = "command";
      command = "~/.local/bin/claude-file-suggestion.sh";
    };
    hooks = {
      Stop = [];
      Notification = [{
        hooks = [{
          type = "command";
          command = "~/.local/bin/claude-notify.sh";
        }];
      }];
      UserPromptSubmit = [{
        matcher = "*";
        hooks = [{
          type = "command";
          command = "~/.local/bin/claude-dismiss-notification.sh";
        }];
      }];
    };
    statusLine = {
      type = "command";
      command = "~/.local/bin/claude-statusline.sh";
    };
    alwaysThinkingEnabled = true;
    attribution = {
      commit = "";
      pr = "";
    };
  } // (cfg.extraSettings or {});

  managedSettingsFile = pkgs.writeText "claude-managed-settings.json" (builtins.toJSON managedSettings);

  mergeScript = pkgs.writeShellScript "merge-claude-settings" ''
    SETTINGS="$HOME/.claude/settings.json"
    ${mkdir} -p "$HOME/.claude"
    if [ -f "$SETTINGS" ] && ${jq} empty "$SETTINGS" 2>/dev/null; then
      ${jq} -s '.[0] * .[1]' "$SETTINGS" ${managedSettingsFile} > "$SETTINGS.tmp" && ${mv} "$SETTINGS.tmp" "$SETTINGS"
    else
      ${cp} ${managedSettingsFile} "$SETTINGS"
    fi
  '';

in
lib.mkIf enable {
  home.packages =
    [ pkgs.unstable.claude-code ]
    ++ lib.optionals isDarwin [ pkgs.terminal-notifier ]
    ++ lib.optionals (!isDarwin) [ pkgs.libnotify ];

  home.file.".local/bin/claude-file-suggestion.sh" = {
    executable = true;
    text = fileSuggestionScript;
  };

  home.file.".local/bin/claude-notify.sh" = {
    executable = true;
    text = notifyScript;
  };

  home.file.".local/bin/claude-statusline.sh" = {
    executable = true;
    text = statusLineScript;
  };

  home.file.".local/bin/claude-dismiss-notification.sh" = {
    executable = true;
    text = dismissScript;
  };

  home.activation.mergeClaudeSettings = {
    after = ["writeBoundary"];
    before = [];
    data = ''
      $DRY_RUN_CMD ${mergeScript}
    '';
  };
}
