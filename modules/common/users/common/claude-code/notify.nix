{ pkgs, isDarwin }:
let
  jq = "${pkgs.jq}/bin/jq";
  git = "${pkgs.git}/bin/git";
  cat = "${pkgs.coreutils}/bin/cat";
  basename = "${pkgs.coreutils}/bin/basename";

  gitContextBlock = ''
    TITLE="Claude Code"
    GROUP_ID="claude-code-default"

    if [ -n "$SESSION_ID" ]; then
      GROUP_ID="claude-code-$SESSION_ID"
    fi

    if ${git} rev-parse --is-inside-work-tree &>/dev/null; then
      PROJECT=$(${basename} "$(${git} rev-parse --show-toplevel 2>/dev/null)")
      BRANCH=$(${git} branch --show-current 2>/dev/null || echo "detached")
      GIT_DIR=$(${git} rev-parse --git-dir 2>/dev/null)
      GIT_COMMON_DIR=$(${git} rev-parse --git-common-dir 2>/dev/null)

      if [ "$GIT_DIR" != "$GIT_COMMON_DIR" ]; then
        WORKTREE_NAME=$(${basename} "$(pwd)")
        TITLE="$PROJECT [worktree: $WORKTREE_NAME @ $BRANCH]"
      else
        TITLE="$PROJECT @ $BRANCH"
      fi
    fi

    if [ -n "$NOTIFICATION_TYPE" ]; then
      DISPLAY_MESSAGE="$NOTIFICATION_TYPE: $MESSAGE"
    else
      DISPLAY_MESSAGE="$MESSAGE"
    fi
  '';

  darwinNotifyScript = let tn = "${pkgs.terminal-notifier}/bin/terminal-notifier"; in ''
    #!/bin/bash
    if [ -t 0 ]; then
      MESSAGE="''${1:-Task completed}"
      SOUND_TYPE="''${2:-default}"
      NOTIFICATION_TYPE=""
      SESSION_ID=""
    else
      INPUT=$(${cat})
      MESSAGE=$(echo "$INPUT" | ${jq} -r '.message // "Task completed"')
      NOTIFICATION_TYPE=$(echo "$INPUT" | ${jq} -r '.notification_type // empty')
      SESSION_ID=$(echo "$INPUT" | ${jq} -r '.session_id // empty')

      case "$NOTIFICATION_TYPE" in
        "permission_prompt") SOUND_TYPE="input" ;;
        "idle_prompt") SOUND_TYPE="input" ;;
        *) SOUND_TYPE="complete" ;;
      esac
    fi

    ${gitContextBlock}

    case "$SOUND_TYPE" in
      input)    SOUND="Basso" ;;
      complete) SOUND="Glass" ;;
      *)        SOUND="default" ;;
    esac

    ${tn} -title "$TITLE" -message "$DISPLAY_MESSAGE" -sound "$SOUND" -group "$GROUP_ID"
  '';

  linuxNotifyScript = let ns = "${pkgs.libnotify}/bin/notify-send"; in ''
    #!/bin/bash
    if [ -t 0 ]; then
      MESSAGE="''${1:-Task completed}"
      NOTIFICATION_TYPE=""
      SESSION_ID=""
    else
      INPUT=$(${cat})
      MESSAGE=$(echo "$INPUT" | ${jq} -r '.message // "Task completed"')
      NOTIFICATION_TYPE=$(echo "$INPUT" | ${jq} -r '.notification_type // empty')
      SESSION_ID=$(echo "$INPUT" | ${jq} -r '.session_id // empty')
    fi

    ${gitContextBlock}

    case "$NOTIFICATION_TYPE" in
      "permission_prompt"|"idle_prompt") URGENCY="critical" ;;
      *) URGENCY="normal" ;;
    esac

    ${ns} -u "$URGENCY" "$TITLE" "$DISPLAY_MESSAGE"
  '';
in
if isDarwin then darwinNotifyScript else linuxNotifyScript
