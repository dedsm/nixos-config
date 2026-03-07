{ pkgs }:
let
  jq = "${pkgs.jq}/bin/jq";
  rg = "${pkgs.ripgrep}/bin/rg";
  fzf = "${pkgs.fzf}/bin/fzf";
  sort = "${pkgs.coreutils}/bin/sort";
  head = "${pkgs.coreutils}/bin/head";
  zsh = "${pkgs.zsh}/bin/zsh";
in ''
  #!${zsh}
  QUERY=$(${jq} -r '.query // ""')
  PROJECT_DIR="''${CLAUDE_PROJECT_DIR:-.}"
  cd "$PROJECT_DIR" || exit 1

  {
    ${rg} --files --follow --hidden -g '!.git/' . 2>/dev/null
  } | ${sort} -u | ${fzf} --filter "$QUERY" | ${head} -15
''
