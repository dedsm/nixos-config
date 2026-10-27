{
  lib,
  homeManagerConfig,
  pkgs,
  ...
}:
let
  cfg = homeManagerConfig.claude-code or { };
  enable = cfg.enable or false;
  isDarwin = pkgs.stdenv.isDarwin;

  # Claude Code package, pinned to an exact release.
  #
  # `claude-code` moves fast enough that whatever `pkgs.unstable` happens to
  # carry isn't reliable, so we pin. The pin is upstream's *own* release
  # manifest, stored verbatim as manifest.zst.json and fed back through the
  # package's `manifest` argument — nixpkgs derives the version, the download
  # URL and the per-platform checksum from it, exactly as it does for its
  # vendored copy. Overriding `src`/`version` by hand instead would re-state
  # upstream's URL scheme and artifact layout here, which is precisely how this
  # drifted before: upstream moved to zstd-compressed artifacts on a new host,
  # and the hand-rolled src kept fetching a raw binary that no longer unpacked.
  #
  # Bump with `scripts/update-packages.sh claude-code`, which runs
  # scripts/updaters/update-claude-code.sh to refetch the manifest.
  claudeCodePkg = pkgs.unstable.claude-code.override {
    manifest = lib.importJSON ./manifest.zst.json;
  };

  # Nix store paths for commands used only in this file
  jq = "${pkgs.jq}/bin/jq";
  mv = "${pkgs.coreutils}/bin/mv";
  cp = "${pkgs.coreutils}/bin/cp";
  mkdir = "${pkgs.coreutils}/bin/mkdir";

  # Import script modules
  claudeIcon = import ./icon.nix { inherit pkgs; };
  iconPath = if isDarwin then claudeIcon.pngPath else claudeIcon.svgPath;

  fileSuggestionScript = import ./file-suggestion.nix { inherit pkgs; };
  notifyScriptDefault = import ./notify.nix { inherit pkgs isDarwin iconPath; };
  dismissScriptDefault = import ./dismiss.nix { inherit pkgs isDarwin; };
  statusLineScript = import ./statusline.nix { inherit pkgs; };

  # Hook entries contributed by the shared agent-harness plugins. This module
  # stays the only writer of settings.json, so it splices them in itself.
  agentHarness = import ../agent-harness/lib.nix { inherit lib pkgs homeManagerConfig; };

  notifyScript = cfg.notifyScript or notifyScriptDefault;
  dismissScript = cfg.dismissScript or dismissScriptDefault;

  # === Managed Settings ===
  managedSettings = {
    fileSuggestion = {
      type = "command";
      command = "~/.local/bin/claude-file-suggestion.sh";
    };
    hooks = {
      Stop = [ ];

      # Owned by the agent-harness module (the rtk rewrite hook, when its
      # `agent-harness.rtk.claude-code` flag is on). An empty list when off,
      # which clears the entry: see the note on Notification below.
      PreToolUse = agentHarness.claudeCode.preToolUse;
      # Likewise, from `agent-harness.rtk-posthook.claude-code`. Owned outright
      # like the keys below, so an entry something else adds here is replaced.
      PostToolUse = agentHarness.claudeCode.postToolUse;

      # Desktop notifications are herdr's job now: it sees every recognised
      # agent rather than just Claude Code, and `prefix+o` jumps to the pane
      # that raised one, which a shell notification popup cannot do. Leaving these hooks
      # enabled would notify twice for the same prompt. See "Notifications" in
      # docs/herdr.md.
      #
      # These must stay as empty *lists* rather than being deleted:
      # `mergeClaudeSettings` merges with `jq -s '.[0] * .[1]'`, so a key
      # dropped from managedSettings keeps whatever value is already in
      # ~/.claude/settings.json instead of going away. The scripts themselves
      # are still installed below, so re-enabling is a one-line revert.
      Notification = [ ];

      # Only ever existed to dismiss the notification the hook above raised.
      UserPromptSubmit = [ ];

      # Owned by the agent-harness module (the brain plugin's health hook, when
      # `agent-harness.brain.claude-code` is on). Unlike the empty-list keys
      # above, SessionStart is SHARED: herdr's integration installs its own
      # entry here (docs/herdr.md), so the merge script array-merges this key
      # instead of letting `*` replace it — user entries survive, the managed
      # entry is (re)appended by command.
      SessionStart = agentHarness.claudeCode.sessionStart;
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
    env = {
      # Exposes the TaskCreate/TaskGet/TaskList/TaskUpdate tools to the model.
      # For the models on Claude Code's gate list they are otherwise withheld
      # unless a server-side feature flag turns them on, and TodoWrite is gated
      # off by the same switch — so a session gets no task tracking at all.
      # See docs/claude-code.md § Task tools.
      CLAUDE_CODE_ENABLE_TODO_TOOLS = "1";
      # Raises the per-session WebSearch cap so long research sessions don't
      # hit it. See docs/claude-code.md § Web search cap.
      CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION = "10000";
      # Opts out of usage metrics and error reports to Anthropic. Also turns
      # off feature-flag evaluation, which can make Remote Control
      # unavailable. See docs/claude-code.md § Telemetry.
      DISABLE_TELEMETRY = "1";
      DISABLE_ERROR_REPORTING = "1";
    };
  }
  // (cfg.extraSettings or { });

  managedSettingsFile = pkgs.writeText "claude-managed-settings.json" (
    builtins.toJSON managedSettings
  );

  # Deep-merge (`*`) recurses into objects but REPLACES arrays — fine for the
  # hook keys this module owns outright (the empty lists above), wrong for
  # hooks.SessionStart, which herdr's integration also writes an entry into
  # (docs/herdr.md): replacing the array would silently delete herdr's hook on
  # every switch. SessionStart is therefore array-merged after the deep merge:
  # user-installed entries survive (minus any stale copy of the managed one,
  # matched by its command path), and the managed entry is appended.
  brainHealthHookPath = agentHarness.claudeCode.brainHealthCommand;
  mergeScript = pkgs.writeShellScript "merge-claude-settings" ''
    SETTINGS="$HOME/.claude/settings.json"
    ${mkdir} -p "$HOME/.claude"
    if [ -f "$SETTINGS" ] && ${jq} empty "$SETTINGS" 2>/dev/null; then
      ${jq} -s '
        (.[0] // {}) as $user | .[1] as $managed
        | ($user * $managed)
        | .hooks.SessionStart =
            ((($user.hooks.SessionStart // [])
              | map(select(([.hooks[]?.command] | index("${brainHealthHookPath}")) | not)))
             + ($managed.hooks.SessionStart // []))
      ' "$SETTINGS" ${managedSettingsFile} > "$SETTINGS.tmp" && ${mv} "$SETTINGS.tmp" "$SETTINGS"
    else
      ${cp} ${managedSettingsFile} "$SETTINGS"
    fi
  '';

in
lib.mkIf enable ({
  home.packages = [
    claudeCodePkg
  ]
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
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      $DRY_RUN_CMD ${mergeScript}
    '';
  };
})
