{ pkgs, isDarwin }:
let
  jq = "${pkgs.jq}/bin/jq";
  cat = "${pkgs.coreutils}/bin/cat";

  zsh = "${pkgs.zsh}/bin/zsh";

  darwinDismissScript = let notify = "$HOME/Applications/CLINotify.app/Contents/MacOS/cli-notify"; in ''
    #!${zsh}
    if [ ! -t 0 ]; then
      INPUT=$(${cat})
      SESSION_ID=$(echo "$INPUT" | ${jq} -r '.session_id // empty')
      if [ -n "$SESSION_ID" ]; then
        GROUP_ID="claude-code-$SESSION_ID"
        ${notify} --remove "$GROUP_ID" 2>/dev/null
      fi
    fi
  '';

  linuxDismissScript = let dbus = "${pkgs.dbus}/bin/dbus-send"; in ''
    #!${zsh}
    # Consume stdin if present (hook mode sends JSON)
    if [ ! -t 0 ]; then
      INPUT=$(${cat})
      SESSION_ID=$(echo "$INPUT" | ${jq} -r '.session_id // empty')
      
      GROUP_ID="claude-code-default"
      if [ -n "$SESSION_ID" ]; then
        GROUP_ID="claude-code-$SESSION_ID"
      fi

      ID_FILE="/tmp/claude-code-notify-$GROUP_ID.id"
      if [ -f "$ID_FILE" ]; then
        OLD_ID=$(${cat} "$ID_FILE")
        if [ -n "$OLD_ID" ]; then
          ${dbus} --type=method_call --dest=org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications.CloseNotification uint32:"$OLD_ID" 2>/dev/null || true
          rm -f "$ID_FILE"
        fi
      fi
    fi
  '';
in
if isDarwin then darwinDismissScript else linuxDismissScript
