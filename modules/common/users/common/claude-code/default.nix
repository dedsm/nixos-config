{ lib, homeManagerConfig, pkgs, ... }:
let
  cfg = homeManagerConfig.claude-code or {};
  enable = cfg.enable or false;
  isDarwin = pkgs.stdenv.isDarwin;

  # Nix store paths for commands used only in this file
  jq = "${pkgs.jq}/bin/jq";
  git = "${pkgs.git}/bin/git";
  cat = "${pkgs.coreutils}/bin/cat";
  basename = "${pkgs.coreutils}/bin/basename";
  mv = "${pkgs.coreutils}/bin/mv";
  cp = "${pkgs.coreutils}/bin/cp";
  mkdir = "${pkgs.coreutils}/bin/mkdir";

  # Import script modules
  fileSuggestionScript = import ./file-suggestion.nix { inherit pkgs; };
  notifyScriptDefault = import ./notify.nix { inherit pkgs isDarwin; };
  dismissScriptDefault = import ./dismiss.nix { inherit pkgs isDarwin; };

  notifyScript = cfg.notifyScript or notifyScriptDefault;
  dismissScript = cfg.dismissScript or dismissScriptDefault;

  # === Status Line ===
  # Using regular "..." string to avoid ''...'' escaping issues with shell's ''
  statusLineCommand = "input=$(${cat}); model=$(echo \"$input\" | ${jq} -r '.model.display_name'); dir=$(${basename} \"$(echo \"$input\" | ${jq} -r '.workspace.current_dir')\"); branch=$(${git} -C \"$(echo \"$input\" | ${jq} -r '.workspace.current_dir')\" branch --show-current 2>/dev/null || echo 'no-git'); remaining=$(echo \"$input\" | ${jq} -r '.context_window.remaining_percentage // empty'); ctx_display=''; [ -n \"$remaining\" ] && ctx_display=\"Context Left: \${remaining}% │ \"; if [ \"$dir\" = \"$branch\" ]; then loc=\"📍 $dir\"; else loc=\"📁 $dir │ 🌿 $branch\"; fi; printf \"%s%s │ %s\" \"$ctx_display\" \"$model\" \"$loc\"";

  # === Managed Settings ===
  managedSettings = {
    fileSuggestion = {
      type = "command";
      command = "~/.local/bin/file-suggestion.sh";
    };
    hooks = {
      Stop = [];
      Notification = [{
        hooks = [{
          type = "command";
          command = "~/.local/bin/notify.sh";
        }];
      }];
      UserPromptSubmit = [{
        matcher = "*";
        hooks = [{
          type = "command";
          command = "~/.local/bin/dismiss-claude-notification.sh";
        }];
      }];
    };
    statusLine = {
      type = "command";
      command = statusLineCommand;
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

  home.file.".local/bin/file-suggestion.sh" = {
    executable = true;
    text = fileSuggestionScript;
  };

  home.file.".local/bin/notify.sh" = {
    executable = true;
    text = notifyScript;
  };

  home.file.".local/bin/dismiss-claude-notification.sh" = {
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
