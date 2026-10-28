# The `brain` plugin's build products: the CLI, the ~/brain commit hooks, the
# per-harness SessionStart health hooks and the weekly notifier. Imported by
# ./default.nix, which installs them. See docs/brain-skill.md.
{ pkgs }:
let
  isDarwin = pkgs.stdenv.isDarwin;
  jq = "${pkgs.jq}/bin/jq";
  git = "${pkgs.git}/bin/git";

  # The skill's source: SKILL.md (the mechanism), brain.py (the CLI) and
  # templates/ (the canonical manual + store scaffold).
  skillDir = ./skills/brain;

  # `brain` CLI — deterministic frontmatter tooling for the ~/brain store
  # (schema/check/reindex/query + the constrained writers new/set/done). Stdlib
  # Python only, so no dependency wiring; patchShebangs points it at the Nix
  # python3. This binary is the single source of truth for the store schema and
  # the pre-commit gate below; it must only ever change via this repo.
  cli = pkgs.runCommandLocal "brain-cli" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    install -Dm755 ${skillDir}/brain.py $out/bin/brain
    # `brain sync` refreshes the store from the canonical template; bake in
    # where this build's template lives (BRAIN_TEMPLATE_DIR still overrides).
    substituteInPlace $out/bin/brain \
      --replace-fail '@brainTemplateDir@' '${skillDir}/templates'
    patchShebangs $out/bin/brain
  '';

  # `brain health`'s one line, plus what the agent should do about it. Shared
  # by both harnesses' SessionStart hooks; only the skill's invocation differs.
  healthContext =
    syncHint:
    ''"~/brain store health (from `brain health`): " + $m + "\nOffer its remedy (e.g. \"run brain sync\" -> offer ${syncHint}; oversized log -> offer brain rotate-log) in your first reply, even if the user asked about something else. If they decline or ignore it, drop it for the rest of the session - never nag twice."'';
in
{
  inherit skillDir cli;

  # The commit hooks installed into ~/brain/.git/hooks by the activation script.
  # Nix is the single installer (the CLI has no `install-hooks` verb), so there is
  # exactly one definition of each hook and no way for it to drift. All real logic
  # lives in the CLI, so the hook files themselves never need to change.
  #
  # pre-commit gate: regenerate index.md + people.md's generated column from
  # frontmatter and stage them (so neither can drift in a commit — no reliance
  # on anyone remembering to reindex), then validate the staged pages. Unlike
  # index.md, people.md is mostly hand-maintained judgment content, so it is
  # staged only when it had no unstaged edits BEFORE the reindex — an
  # in-progress hand edit must not be swept into an unrelated commit (and
  # auto-pushed); the column refresh rides the next clean commit instead.
  # Separate `git add`s: a store without people.md must still stage index.md.
  preCommitHook = pkgs.writeShellScript "brain-pre-commit" ''
    people_clean=
    ${git} diff --quiet -- mocs/people.md 2>/dev/null && people_clean=1
    ${cli}/bin/brain reindex >/dev/null 2>&1 || true
    ${git} add -- index.md >/dev/null 2>&1 || true
    if [ -n "$people_clean" ]; then
      ${git} add -- mocs/people.md >/dev/null 2>&1 || true
    fi
    exec ${cli}/bin/brain check --staged
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
  postCommitHook = pkgs.writeShellScript "brain-post-commit" ''
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    # Recursion stop: git runs post-commit again for commits the pull --rebase
    # below replays. During a rebase HEAD is detached, so the symbolic-ref
    # check already exits those inner runs; the env guard is belt and braces.
    [ -n "$BRAIN_AUTOPUSH" ] && exit 0
    export BRAIN_AUTOPUSH=1
    export GIT_SSH_COMMAND="''${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}"
    git=${git}
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

  # Claude Code SessionStart hook: surface `brain health` — one deterministic
  # line of store vitals (version drift, overdue, gone-quiet, aged inbox, quiet
  # log, oversized log, now.md rot, ahead/behind remote) — at the start of every
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
  claudeHealthHook = pkgs.writeShellScript "claude-brain-health" ''
    out=$(${cli}/bin/brain health 2>/dev/null) || true
    if [ -n "$out" ]; then
      ${jq} -n --arg m "$out" '{
        systemMessage: ("brain health: " + $m),
        hookSpecificOutput: {
          hookEventName: "SessionStart",
          additionalContext: (${healthContext "/brain --sync"})
        }
      }'
    fi
    exit 0
  '';

  # The same line for Antigravity, whose SessionStart contract is a JSON object
  # on stdout (`{}` when there is nothing to say) with the text as a step to
  # inject. Same fail-open, always-exit-0 behaviour.
  antigravityHealthHook = pkgs.writeShellScript "antigravity-brain-health" ''
    out=$(${cli}/bin/brain health 2>/dev/null) || true
    if [ -n "$out" ]; then
      ${jq} -n --arg m "$out" '{
        injectSteps: [{ systemMessage: { systemMessage: (${healthContext "to run the brain skill with --sync"}) } }]
      }'
    else
      echo '{}'
    fi
    exit 0
  '';

  # The weekly ambient check: health's whole reason to exist is that pull-only
  # signals were never seen when no session happened. Exit-code contract: health
  # is silent+0 when clean, prints one line and exits 1 on any breach.
  healthNotify = pkgs.writeShellScript "brain-health-notify" ''
    out=$(${cli}/bin/brain health 2>/dev/null) && exit 0
    [ -n "$out" ] || exit 0
    ${
      if isDarwin then
        ''"$HOME/Applications/CLINotify.app/Contents/MacOS/cli-notify" --title "brain health" --message "$out"''
      else
        ''${pkgs.libnotify}/bin/notify-send -a brain "brain health" "$out"''
    }
  '';
}
