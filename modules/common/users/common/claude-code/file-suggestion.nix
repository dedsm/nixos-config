{ pkgs }:
let
  jq = "${pkgs.jq}/bin/jq";
  fd = "${pkgs.fd}/bin/fd";
  fzf = "${pkgs.fzf}/bin/fzf";
  head = "${pkgs.coreutils}/bin/head";
  zsh = "${pkgs.zsh}/bin/zsh";
in ''
  #!${zsh}
  QUERY=$(${jq} -r '.query // ""')
  PROJECT_DIR="''${CLAUDE_PROJECT_DIR:-.}"
  cd "$PROJECT_DIR" || exit 1

  ${fd} --hidden --follow --exclude .git . 2>/dev/null \
    | ${fzf} --filter "$QUERY" | ${head} -15
''
