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

  # Claude Code package with optional version pin via version.json
  # Bump with `scripts/update-packages.sh claude-code`, which runs
  # scripts/updaters/update-claude-code.sh to fetch the latest version and hashes
  baseClaudeCode = pkgs.unstable.claude-code;
  versionFile = ./version.json;
  hasVersionPin = builtins.pathExists versionFile;
  claudeCodePkg =
    if hasVersionPin then
      let
        pin = lib.importJSON versionFile;
        platformKey = "${if isDarwin then "darwin" else "linux"}-${
          if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x64"
        }";
      in
      baseClaudeCode.overrideAttrs (old: rec {
        version = pin.version;
        src = pkgs.fetchurl {
          url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${platformKey}/claude";
          sha256 = pin.platforms.${platformKey};
        };
      })
    else
      baseClaudeCode;

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
  # pre-commit gate: regenerate index.md from frontmatter and stage it (so the
  # catalog can never drift in a commit — no reliance on anyone remembering to
  # reindex), then validate the staged pages.
  brainPreCommitHook = pkgs.writeShellScript "brain-pre-commit" ''
    ${brainPkg}/bin/brain reindex >/dev/null 2>&1 || true
    ${pkgs.git}/bin/git add -- index.md >/dev/null 2>&1 || true
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
  # log, now.md rot, ahead/behind remote) — as context at the start of every
  # Claude Code session. No model in the loop, silent when the store is clean or
  # absent, and fail-open (always exits 0) so a broken store can't block a session.
  brainHealthHook = pkgs.writeShellScript "claude-brain-health" ''
    out=$(${brainPkg}/bin/brain health 2>/dev/null) || true
    if [ -n "$out" ]; then
      printf '~/brain store health (from `brain health`): %s\n' "$out"
      printf 'If the user engages with it, address it via the brain skill; otherwise mention it briefly at most once.\n'
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
