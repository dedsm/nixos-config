{ pkgs }:
let
  jq = "${pkgs.jq}/bin/jq";
  fd = "${pkgs.fd}/bin/fd";
  fzf = "${pkgs.fzf}/bin/fzf";
  head = "${pkgs.coreutils}/bin/head";
  cat = "${pkgs.coreutils}/bin/cat";
  bash = "${pkgs.bash}/bin/bash";
in ''
  #!${bash}
  INPUT=$(${cat})
  QUERY=$(echo "$INPUT" | ${jq} -r '.query // ""')
  CWD=$(echo "$INPUT" | ${jq} -r '.cwd // "."')
  
  PROJECT_DIR="''${CLAUDE_PROJECT_DIR:-$CWD}"
  if [[ -d "$PROJECT_DIR" ]]; then
    PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)
  fi

  # Expand ~ to $HOME
  REAL_QUERY="''${QUERY/#\~/$HOME}"

  RESULTS=""
  SEARCH_BASE=""
  FILTER_QUERY=""
  MAX_DEPTH=""

  if [[ "$REAL_QUERY" == /* ]]; then
    if [[ -d "$REAL_QUERY" ]]; then
      SEARCH_BASE="$REAL_QUERY"
      FILTER_QUERY=""
    else
      SEARCH_BASE=$(dirname "$REAL_QUERY")
      FILTER_QUERY=$(basename "$REAL_QUERY")
    fi
    MAX_DEPTH="4"
  else
    SEARCH_BASE="$PROJECT_DIR"
    FILTER_QUERY="$QUERY"
    MAX_DEPTH=""
  fi

  if [[ -d "$SEARCH_BASE" ]]; then
    DEPTH_FLAG=""
    [[ -n "$MAX_DEPTH" ]] && DEPTH_FLAG="--max-depth $MAX_DEPTH"

    # Run the search, clearing any FZF environment variables that might interfere
    RAW_RESULTS=$(export FZF_DEFAULT_OPTS=""; export FZF_DEFAULT_COMMAND=""; ${fd} --hidden $DEPTH_FLAG --exclude .git . "$SEARCH_BASE" 2>/dev/null | ${fzf} --filter "$FILTER_QUERY" | ${head} -15)
    
    if [[ -n "$RAW_RESULTS" ]]; then
      if [[ "$SEARCH_BASE" == "$PROJECT_DIR"* ]]; then
        RESULTS=$(echo "$RAW_RESULTS" | sed "s|^''${PROJECT_DIR%/}/||")
      else
        RESULTS="$RAW_RESULTS"
      fi
    fi
  fi

  # Fallback
  if [[ -z "$RESULTS" && "$SEARCH_BASE" != "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
    RESULTS=$(export FZF_DEFAULT_OPTS=""; export FZF_DEFAULT_COMMAND=""; ${fd} --hidden --exclude .git . "$PROJECT_DIR" 2>/dev/null | ${fzf} --filter "$QUERY" | ${head} -15 | sed "s|^''${PROJECT_DIR%/}/||")
  fi

  if [[ -n "$RESULTS" ]]; then
    echo "$RESULTS"
  fi
''
