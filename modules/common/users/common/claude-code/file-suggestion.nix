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
  DEBUG_LOG="/tmp/claude_suggestion_debug.log"
  exec 2>>"$DEBUG_LOG" # Redirect stderr to debug log
  
  echo "--- $(date) ---" >> "$DEBUG_LOG"

  INPUT=$(${cat})
  echo "Input JSON: $INPUT" >> "$DEBUG_LOG"

  QUERY=$(echo "$INPUT" | ${jq} -r '.query // ""')
  CWD=$(echo "$INPUT" | ${jq} -r '.cwd // "."')
  
  PROJECT_DIR="''${CLAUDE_PROJECT_DIR:-$CWD}"
  # Make PROJECT_DIR absolute safely
  if [[ -d "$PROJECT_DIR" ]]; then
    PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)
  fi

  echo "Query: $QUERY" >> "$DEBUG_LOG"
  echo "Project Dir: $PROJECT_DIR" >> "$DEBUG_LOG"

  # Expand ~ to $HOME
  REAL_QUERY="''${QUERY/#\~/$HOME}"
  echo "Real Query: $REAL_QUERY" >> "$DEBUG_LOG"

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
    echo "Search Base: $SEARCH_BASE" >> "$DEBUG_LOG"
    echo "Filter Query: $FILTER_QUERY" >> "$DEBUG_LOG"

    DEPTH_FLAG=""
    [[ -n "$MAX_DEPTH" ]] && DEPTH_FLAG="--max-depth $MAX_DEPTH"

    # Use a simpler pipe and capture everything
    echo "FD Check (first 1): $(${fd} --hidden $DEPTH_FLAG --exclude .git . "$SEARCH_BASE" 2>/dev/null | ${head} -n 1)" >> "$DEBUG_LOG"

    # Run the search, clearing any FZF environment variables that might interfere
    RAW_RESULTS=$(export FZF_DEFAULT_OPTS=""; export FZF_DEFAULT_COMMAND=""; ${fd} --hidden $DEPTH_FLAG --exclude .git . "$SEARCH_BASE" 2>/dev/null | ${fzf} --filter "$FILTER_QUERY" | ${head} -15)
    
    if [[ -n "$RAW_RESULTS" ]]; then
      echo "Found raw results" >> "$DEBUG_LOG"
      # Strip PROJECT_DIR prefix if results are within it
      if [[ "$SEARCH_BASE" == "$PROJECT_DIR"* ]]; then
        RESULTS=$(echo "$RAW_RESULTS" | sed "s|^''${PROJECT_DIR%/}/||")
      else
        RESULTS="$RAW_RESULTS"
      fi
    else
      echo "No raw results found for command: ${fd} --hidden $DEPTH_FLAG --exclude .git . \"$SEARCH_BASE\" | fzf --filter \"$FILTER_QUERY\"" >> "$DEBUG_LOG"
    fi
  fi

  # Fallback
  if [[ -z "$RESULTS" && "$SEARCH_BASE" != "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
    echo "Fallback to project dir search" >> "$DEBUG_LOG"
    RESULTS=$(export FZF_DEFAULT_OPTS=""; export FZF_DEFAULT_COMMAND=""; ${fd} --hidden --exclude .git . "$PROJECT_DIR" 2>/dev/null | ${fzf} --filter "$QUERY" | ${head} -15 | sed "s|^''${PROJECT_DIR%/}/||")
  fi

  if [[ -n "$RESULTS" ]]; then
    echo "Returning Results count: $(echo "$RESULTS" | grep -c . || echo 0)" >> "$DEBUG_LOG"
    echo "$RESULTS"
  else
    echo "Returning EMPTY RESULTS" >> "$DEBUG_LOG"
  fi
''
