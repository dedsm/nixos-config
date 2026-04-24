{ pkgs, isDarwin, iconPath }:
let
  jq = "${pkgs.jq}/bin/jq";
  cat = "${pkgs.coreutils}/bin/cat";
  basename = "${pkgs.coreutils}/bin/basename";

  tmux = "${pkgs.tmux}/bin/tmux";

  gitContextBlock = ''
    GROUP_ID="claude-code-default"

    if [ -n "$SESSION_ID" ]; then
      GROUP_ID="claude-code-$SESSION_ID"
    fi

    # Use tmux window name as title if available (matches what the user sees)
    if [ -n "$TMUX" ] && [ -n "$TMUX_PANE" ]; then
      TITLE=$(${tmux} display-message -p -t "$TMUX_PANE" '#{window_name}' 2>/dev/null)
    fi

    if [ -z "$TITLE" ]; then
      TITLE="Claude Code $(${basename} "$(pwd)")"
    fi

    if [ -n "$NOTIFICATION_TYPE" ]; then
      DISPLAY_MESSAGE="$NOTIFICATION_TYPE: $MESSAGE"
    else
      DISPLAY_MESSAGE="$MESSAGE"
    fi
  '';

  zsh = "${pkgs.zsh}/bin/zsh";

  darwinNotifyScript = let notify = "$HOME/Applications/CLINotify.app/Contents/MacOS/cli-notify"; in ''
    #!${zsh}
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

    ${notify} --title "$TITLE" --message "$DISPLAY_MESSAGE" --sound "$SOUND" --group "$GROUP_ID"
  '';

  linuxNotifyScript = let ns = "${pkgs.libnotify}/bin/notify-send"; in ''
    #!${zsh}
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

    ID_FILE="/tmp/claude-code-notify-$GROUP_ID.id"
    if [ -f "$ID_FILE" ]; then
      OLD_ID=$(${cat} "$ID_FILE")
      if [ -n "$OLD_ID" ]; then
        NEW_ID=$(${ns} -p -i ${iconPath} -r "$OLD_ID" -u "$URGENCY" "$TITLE" "$DISPLAY_MESSAGE")
      else
        NEW_ID=$(${ns} -p -i ${iconPath} -u "$URGENCY" "$TITLE" "$DISPLAY_MESSAGE")
      fi
    else
      NEW_ID=$(${ns} -p -i ${iconPath} -u "$URGENCY" "$TITLE" "$DISPLAY_MESSAGE")
    fi

    if [ -n "$NEW_ID" ]; then
      echo "$NEW_ID" > "$ID_FILE"
    fi
  '';
in
if isDarwin then darwinNotifyScript else linuxNotifyScript
