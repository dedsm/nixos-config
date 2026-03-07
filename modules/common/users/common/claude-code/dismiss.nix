{ pkgs, isDarwin }:
let
  jq = "${pkgs.jq}/bin/jq";
  cat = "${pkgs.coreutils}/bin/cat";

  zsh = "${pkgs.zsh}/bin/zsh";

  darwinDismissScript = let tn = "${pkgs.terminal-notifier}/bin/terminal-notifier"; in ''
    #!${zsh}
    if [ ! -t 0 ]; then
      INPUT=$(${cat})
      SESSION_ID=$(echo "$INPUT" | ${jq} -r '.session_id // empty')
      if [ -n "$SESSION_ID" ]; then
        GROUP_ID="claude-code-$SESSION_ID"
        ${tn} -remove "$GROUP_ID" 2>/dev/null
      fi
    fi
  '';

  linuxDismissScript = ''
    #!${zsh}
    # Consume stdin if present (hook mode sends JSON)
    [ ! -t 0 ] && ${cat} > /dev/null
  '';
in
if isDarwin then darwinDismissScript else linuxDismissScript
