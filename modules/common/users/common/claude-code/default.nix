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

  notifyScript = cfg.notifyScript or notifyScriptDefault;
  dismissScript = cfg.dismissScript or dismissScriptDefault;

  # `brain` CLI — deterministic frontmatter tooling for the ~/brain store
  # (schema/check/reindex/query + the constrained writers new/set/done). Stdlib
  # Python only, so no dependency wiring; patchShebangs points it at the Nix
  # python3. This binary is the single source of truth for the store schema and
  # the pre-commit gate below; it must only ever change via this repo.
  brainPkg = pkgs.runCommandLocal "brain-cli" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    install -Dm755 ${./skills/brain/brain.py} $out/bin/brain
    # `brain sync` refreshes the store from the canonical template; bake in
    # where this build's template lives (BRAIN_TEMPLATE_DIR still overrides).
    substituteInPlace $out/bin/brain \
      --replace-fail '@brainTemplateDir@' '${./skills/brain/templates}'
    patchShebangs $out/bin/brain
  '';

  # The commit hooks installed into ~/brain/.git/hooks by the activation script.
  # Nix is the single installer (the CLI has no `install-hooks` verb), so there is
  # exactly one definition of each hook and no way for it to drift. All real logic
  # lives in brainPkg, so the hook files themselves never need to change.
  #
  # pre-commit gate: regenerate index.md + people.md's generated column from
  # frontmatter and stage them (so neither can drift in a commit — no reliance
  # on anyone remembering to reindex), then validate the staged pages. Unlike
  # index.md, people.md is mostly hand-maintained judgment content, so it is
  # staged only when it had no unstaged edits BEFORE the reindex — an
  # in-progress hand edit must not be swept into an unrelated commit (and
  # auto-pushed); the column refresh rides the next clean commit instead.
  # Separate `git add`s: a store without people.md must still stage index.md.
  brainPreCommitHook = pkgs.writeShellScript "brain-pre-commit" ''
    people_clean=
    ${pkgs.git}/bin/git diff --quiet -- mocs/people.md 2>/dev/null && people_clean=1
    ${brainPkg}/bin/brain reindex >/dev/null 2>&1 || true
    ${pkgs.git}/bin/git add -- index.md >/dev/null 2>&1 || true
    if [ -n "$people_clean" ]; then
      ${pkgs.git}/bin/git add -- mocs/people.md >/dev/null 2>&1 || true
    fi
    exec ${brainPkg}/bin/brain check --staged
  '';

  # post-commit auto-push: back the store up to its remote when one is configured,
  # so a commit is also a backup + multi-machine sync (no reliance on anyone
  # remembering `git push`). If the remote has moved — the normal multi-machine
  # case: another machine pushed first — it reconciles automatically: fetch +
  # rebase our commits on top, push again. A rebase that hits real conflicts is
  # aborted (the store is left exactly as committed) with a reconcile hint.
  # Non-fatal by design (the commit already happened), it NEVER force-pushes,
  # and BatchMode keeps it from hanging on an SSH prompt. GIT_DIR is unset
  # because git exports it to hooks, which would break the nested pull.
  brainPostCommitHook = pkgs.writeShellScript "brain-post-commit" ''
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    # Recursion stop: git runs post-commit again for commits the pull --rebase
    # below replays. During a rebase HEAD is detached, so the symbolic-ref
    # check already exits those inner runs; the env guard is belt and braces.
    [ -n "$BRAIN_AUTOPUSH" ] && exit 0
    export BRAIN_AUTOPUSH=1
    export GIT_SSH_COMMAND="''${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}"
    git=${pkgs.git}/bin/git
    $git remote get-url origin >/dev/null 2>&1 || exit 0
    branch=$($git symbolic-ref --short HEAD 2>/dev/null) || exit 0
    $git push --quiet origin "$branch" 2>/dev/null && exit 0
    # Push rejected: the remote likely moved. Rebase on top of it and retry.
    if $git pull --rebase --quiet origin "$branch" >/dev/null 2>&1 \
        && $git push --quiet origin "$branch" 2>/dev/null; then
      echo 'brain: remote had moved — rebased local commit(s) on top and pushed.' >&2
      exit 0
    fi
    $git rebase --abort >/dev/null 2>&1 || true
    echo 'brain: auto-push failed (real conflicts, or remote unreachable). Reconcile with `git -C ~/brain pull --rebase`, resolve, then push — never force.' >&2
    exit 0
  '';

  # SessionStart hook: surface `brain health` — one deterministic line of store
  # vitals (version drift, overdue, gone-quiet, aged inbox, quiet log, oversized
  # log, now.md rot, ahead/behind remote) — at the start of every Claude Code
  # session. No model in the loop, silent when the store is clean or absent, and
  # fail-open (always exits 0) so a broken store can't block a session.
  #
  # The output is JSON rather than plain text because the two audiences need
  # different channels: a SessionStart hook's plain stdout is only added to
  # Claude's *context*, so the user never sees the flag until Claude's first
  # reply. `systemMessage` is rendered to the user directly, while
  # `hookSpecificOutput.additionalContext` carries the context injection — so
  # the flag lands in both places from one run. `brain health`'s line is
  # arbitrary text, so jq builds the object rather than string interpolation.
  brainHealthHook = pkgs.writeShellScript "claude-brain-health" ''
    out=$(${brainPkg}/bin/brain health 2>/dev/null) || true
    if [ -n "$out" ]; then
      ${jq} -n --arg m "$out" '{
        systemMessage: ("brain health: " + $m),
        hookSpecificOutput: {
          hookEventName: "SessionStart",
          additionalContext: ("~/brain store health (from `brain health`): " + $m + "\nOffer its remedy (e.g. \"run brain sync\" -> offer /brain --sync; oversized log -> offer brain rotate-log) in your first reply, even if the user asked about something else. If they decline or ignore it, drop it for the rest of the session - never nag twice.")
        }
      }'
    fi
    exit 0
  '';

  # The weekly ambient check: health's whole reason to exist is that pull-only
  # signals were never seen when no session happened. Exit-code contract: health
  # is silent+0 when clean, prints one line and exits 1 on any breach.
  brainHealthNotify = pkgs.writeShellScript "brain-health-notify" ''
    out=$(${brainPkg}/bin/brain health 2>/dev/null) && exit 0
    [ -n "$out" ] || exit 0
    ${
      if isDarwin then
        ''"$HOME/Applications/CLINotify.app/Contents/MacOS/cli-notify" --title "brain health" --message "$out"''
      else
        ''${pkgs.libnotify}/bin/notify-send -a brain "brain health" "$out"''
    }
  '';

  # === Managed Settings ===
  managedSettings = {
    fileSuggestion = {
      type = "command";
      command = "~/.local/bin/claude-file-suggestion.sh";
    };
    hooks = {
      Stop = [ ];

      # Desktop notifications are herdr's job now: it sees every recognised
      # agent rather than just Claude Code, and `prefix+o` jumps to the pane
      # that raised one, which a swaync popup cannot do. Leaving these hooks
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

      # Ambient store vitals: inject `brain health`'s one-liner (if any) as
      # context when a session starts. Deliberately not on "compact" — the
      # line would repeat mid-task. See docs/brain-skill.md § Ambient surfacing.
      #
      # Unlike the empty-list keys above, SessionStart is SHARED: herdr's
      # integration installs its own entry here (docs/herdr.md), so the merge
      # script array-merges this key instead of letting `*` replace it —
      # user entries survive, this managed entry is (re)appended by command.
      SessionStart = [
        {
          matcher = "startup|resume|clear";
          hooks = [
            {
              type = "command";
              command = brainHealthHookPath;
            }
          ];
        }
      ];
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
  brainHealthHookPath = "~/.local/bin/claude-brain-health.sh";
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
lib.mkIf enable (
  {
    home.packages = [
      claudeCodePkg
      brainPkg
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

    home.file.".local/bin/claude-brain-health.sh".source = brainHealthHook;

    # Personal "brain" tracking store. We manage exactly three things:
    #   1. the skill + its canonical template (the mechanism and the latest conventions),
    #   2. the `brain` CLI (schema/gate/writers, added to home.packages above), and
    #   3. a one-time bootstrap that seeds ~/brain from the template if it is missing,
    #      plus idempotent (re)installation of the commit hooks (pre-commit gate +
    #      post-commit auto-push) on every switch — Nix is their sole installer.
    # The store's living content (pages, index, log) is mutable user data — never
    # symlinked/managed here. The bootstrap is create-if-missing: it never touches an
    # existing store's content. Existing stores catch up to template changes via
    # `/brain --sync`. The hooks are refreshed unconditionally so their store paths
    # always point at the current brainPkg.
    home.file.".claude/skills/brain/SKILL.md".source = ./skills/brain/SKILL.md;
    home.file.".claude/skills/brain/templates".source = ./skills/brain/templates;

    home.activation.bootstrapBrain = {
      after = [ "writeBoundary" ];
      before = [ ];
      data = ''
        brain="$HOME/brain"
        if [ ! -d "$brain" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$brain"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -R ${./skills/brain/templates}/. "$brain"/
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+w "$brain"
          $DRY_RUN_CMD ${pkgs.git}/bin/git -C "$brain" init -q
          # Scaffold pages ship with a sentinel date (a static template cannot know
          # the seeding date); normalize restamps them, then record the version so
          # a fresh store isn't reported as behind.
          $DRY_RUN_CMD env BRAIN_DIR="$brain" ${brainPkg}/bin/brain normalize >/dev/null || true
          $DRY_RUN_CMD env BRAIN_DIR="$brain" ${brainPkg}/bin/brain version --stamp >/dev/null || true
        fi
        # Install/refresh the Nix-managed commit hooks: the pre-commit gate
        # (reindex + validate) and the post-commit auto-push (backup + sync).
        if [ -d "$brain/.git" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$brain/.git/hooks"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m755 ${brainPreCommitHook} "$brain/.git/hooks/pre-commit"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m755 ${brainPostCommitHook} "$brain/.git/hooks/post-commit"
        fi
      '';
    };

    home.activation.mergeClaudeSettings = {
      after = [ "writeBoundary" ];
      before = [ ];
      data = ''
        $DRY_RUN_CMD ${mergeScript}
      '';
    };
  }
  # Weekly `brain health` timer — the ambient half of the surfacing story: the
  # SessionStart hook covers sessions, this covers the days when none happen.
  // lib.optionalAttrs (!isDarwin) {
    systemd.user.services.brain-health = {
      Unit.Description = "brain store health check";
      Service = {
        Type = "oneshot";
        ExecStart = "${brainHealthNotify}";
      };
    };
    systemd.user.timers.brain-health = {
      Unit.Description = "weekly brain store health notification";
      Timer = {
        OnCalendar = "Mon 10:00";
        Persistent = true; # laptop: fire on next wake if the slot was missed
      };
      Install.WantedBy = [ "timers.target" ];
    };
  }
  // lib.optionalAttrs isDarwin {
    launchd.agents.brain-health = {
      enable = true;
      config = {
        ProgramArguments = [ "${brainHealthNotify}" ];
        StartCalendarInterval = [
          {
            Weekday = 1;
            Hour = 10;
            Minute = 0;
          }
        ];
      };
    };
  }
)
