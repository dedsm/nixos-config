{ pkgs, isDarwin }:
let
  jq = "${pkgs.jq}/bin/jq";
  git = "${pkgs.git}/bin/git";
  cat = "${pkgs.coreutils}/bin/cat";
  basename = "${pkgs.coreutils}/bin/basename";

  gitContextBlock = ''
    TITLE="Gemini CLI"
    GROUP_ID="gemini-cli-default"

    if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "null" ]; then
      GROUP_ID="gemini-cli-$SESSION_ID"
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

    if [ -n "$HOOK_EVENT" ] && [ "$HOOK_EVENT" != "null" ]; then
      DISPLAY_MESSAGE="[$HOOK_EVENT] $MESSAGE"
    else
      DISPLAY_MESSAGE="$MESSAGE"
    fi
  '';

  zsh = "${pkgs.zsh}/bin/zsh";

  darwinNotifyScript = let alerter = "/opt/homebrew/bin/alerter"; in ''
    #!${zsh}
    if [ -t 0 ]; then
      MESSAGE="''${1:-Task completed}"
      SOUND_TYPE="''${2:-default}"
      HOOK_EVENT=""
      SESSION_ID=""
    else
      INPUT=$(${cat})
      MESSAGE=$(echo "$INPUT" | ${jq} -r 'if .prompt_response then (.prompt_response[0:100] | sub("\n"; " "; "g") | sub("\r"; " "; "g")) + "..." else "Task completed" end')
      HOOK_EVENT=$(echo "$INPUT" | ${jq} -r '.hook_event_name // empty')
      SESSION_ID=$(echo "$INPUT" | ${jq} -r '.session_id // empty')
      SOUND_TYPE="complete"
    fi

    ${gitContextBlock}

    case "$SOUND_TYPE" in
      input)    SOUND="Basso" ;;
      complete) SOUND="Glass" ;;
      *)        SOUND="default" ;;
    esac

    ${alerter} --title "$TITLE" --message "$DISPLAY_MESSAGE" --sound "$SOUND" --group "$GROUP_ID" --timeout 5 >/dev/null 2>&1

    # Return empty JSON to satisfy Gemini CLI hook requirements
    echo "{}"
  '';

  linuxNotifyScript = let ns = "${pkgs.libnotify}/bin/notify-send"; in ''
    #!${zsh}
    if [ -t 0 ]; then
      MESSAGE="''${1:-Task completed}"
      HOOK_EVENT=""
      SESSION_ID=""
    else
      INPUT=$(${cat})
      MESSAGE=$(echo "$INPUT" | ${jq} -r 'if .prompt_response then (.prompt_response[0:100] | sub("\n"; " "; "g") | sub("\r"; " "; "g")) + "..." else "Task completed" end')
      HOOK_EVENT=$(echo "$INPUT" | ${jq} -r '.hook_event_name // empty')
      SESSION_ID=$(echo "$INPUT" | ${jq} -r '.session_id // empty')
    fi

    ${gitContextBlock}

    URGENCY="normal"

    ${ns} -u "$URGENCY" "$TITLE" "$DISPLAY_MESSAGE" >/dev/null 2>&1

    # Return empty JSON to satisfy Gemini CLI hook requirements
    echo "{}"
  '';
in
if isDarwin then darwinNotifyScript else linuxNotifyScript
