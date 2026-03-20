{ pkgs }:
let
  jq = "${pkgs.jq}/bin/jq";
  git = "${pkgs.git}/bin/git";
  cat = "${pkgs.coreutils}/bin/cat";
  basename = "${pkgs.coreutils}/bin/basename";
  date = "${pkgs.coreutils}/bin/date";
  zsh = "${pkgs.zsh}/bin/zsh";
in ''
  #!${zsh}
  input=$(${cat})

  # ANSI colors
  RESET=$'\033[0m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RED=$'\033[31m'
  CYAN=$'\033[36m'

  # === Model ===
  model=$(echo "$input" | ${jq} -r '.model.display_name // "Unknown"')
  model_section="''${BOLD}Model:''${RESET} ''${CYAN}''${model}''${RESET}"

  # === Context Window ===
  used_pct=$(echo "$input" | ${jq} -r '.context_window.used_percentage // 0')
  total_input=$(echo "$input" | ${jq} -r '.context_window.total_input_tokens // 0')
  total_output=$(echo "$input" | ${jq} -r '.context_window.total_output_tokens // 0')

  cache_create=$(echo "$input" | ${jq} -r '.context_window.current_usage.cache_creation_input_tokens // 0')
  cache_read=$(echo "$input" | ${jq} -r '.context_window.current_usage.cache_read_input_tokens // 0')

  # Format tokens with K suffix
  fmt_tokens() {
    local n=$1
    if (( n >= 1000 )); then
      printf "%.1fK" "$(( n / 1000.0 ))"
    else
      echo "$n"
    fi
  }

  # Color based on usage percentage (zsh float comparison)
  if (( used_pct < 50 )); then
    ctx_color="$GREEN"
  elif (( used_pct < 80 )); then
    ctx_color="$YELLOW"
  else
    ctx_color="$RED"
  fi

  used_fmt=$(printf "%.1f" "$used_pct")
  total_in_fmt=$(fmt_tokens "$total_input")
  total_out_fmt=$(fmt_tokens "$total_output")
  cache_create_fmt=$(fmt_tokens "$cache_create")
  cache_read_fmt=$(fmt_tokens "$cache_read")

  ctx_section="''${BOLD}Context:''${RESET} ''${ctx_color}''${used_fmt}%''${RESET} used"
  ctx_section="''${ctx_section} | ''${DIM}in:''${RESET}''${total_in_fmt} ''${DIM}out:''${RESET}''${total_out_fmt}"
  ctx_section="''${ctx_section} | ''${DIM}cache:''${RESET}''${cache_create_fmt}+''${cache_read_fmt}"

  # === Rate Limits ===
  rl_5h_pct=$(echo "$input" | ${jq} -r '.rate_limits.five_hour.used_percentage // empty')
  rl_7d_pct=$(echo "$input" | ${jq} -r '.rate_limits.seven_day.used_percentage // empty')
  rl_5h_resets=$(echo "$input" | ${jq} -r '.rate_limits.five_hour.resets_at // empty')
  rl_7d_resets=$(echo "$input" | ${jq} -r '.rate_limits.seven_day.resets_at // empty')

  # Format seconds remaining as countdown
  fmt_countdown() {
    local resets_at=$1
    local now=$(${date} +%s)
    local diff=$(( resets_at - now ))
    if (( diff <= 0 )); then
      echo "now"
      return
    fi
    local hours=$(( diff / 3600 ))
    local mins=$(( (diff % 3600) / 60 ))
    if (( hours > 0 )); then
      printf "%dh%dm" "$hours" "$mins"
    else
      printf "%dm" "$mins"
    fi
  }

  rate_section=""
  if [[ -n "$rl_5h_pct" || -n "$rl_7d_pct" ]]; then
    # Color helper for rate limit percentages
    rl_color() {
      local pct=$1
      if (( pct < 50 )); then
        echo "$GREEN"
      elif (( pct < 80 )); then
        echo "$YELLOW"
      else
        echo "$RED"
      fi
    }

    rate_section="''${BOLD}Rate:''${RESET}"
    if [[ -n "$rl_5h_pct" ]]; then
      rl_5h_fmt=$(printf "%.0f" "$rl_5h_pct")
      rl_5h_color=$(rl_color "$rl_5h_pct")
      rl_5h_cd=""
      [[ -n "$rl_5h_resets" ]] && rl_5h_cd=" ''${DIM}↻$(fmt_countdown "$rl_5h_resets")''${RESET}"
      rate_section="''${rate_section} ''${DIM}5h:''${RESET}''${rl_5h_color}''${rl_5h_fmt}%''${RESET}''${rl_5h_cd}"
    fi
    if [[ -n "$rl_7d_pct" ]]; then
      rl_7d_fmt=$(printf "%.0f" "$rl_7d_pct")
      rl_7d_color=$(rl_color "$rl_7d_pct")
      rl_7d_cd=""
      [[ -n "$rl_7d_resets" ]] && rl_7d_cd=" ''${DIM}↻$(fmt_countdown "$rl_7d_resets")''${RESET}"
      rate_section="''${rate_section} ''${DIM}7d:''${RESET}''${rl_7d_color}''${rl_7d_fmt}%''${RESET}''${rl_7d_cd}"
    fi
  fi

  # === Git ===
  work_dir=$(echo "$input" | ${jq} -r '.workspace.current_dir // ""')
  dir_name=$(${basename} "$work_dir")

  if ${git} -C "$work_dir" rev-parse --is-inside-work-tree &>/dev/null; then
    branch=$(${git} -C "$work_dir" branch --show-current 2>/dev/null || echo "detached")

    # Dirty/clean indicator
    if ${git} -C "$work_dir" diff --quiet 2>/dev/null && ${git} -C "$work_dir" diff --staged --quiet 2>/dev/null; then
      status_icon="''${GREEN}✓''${RESET}"
    else
      status_icon="''${RED}●''${RESET}"
    fi

    # Worktree detection
    git_dir=$(${git} -C "$work_dir" rev-parse --git-dir 2>/dev/null)
    git_common_dir=$(${git} -C "$work_dir" rev-parse --git-common-dir 2>/dev/null)

    if [[ "$git_dir" != "$git_common_dir" ]]; then
      wt_name=$(${basename} "$work_dir")
      git_section="''${BOLD}Git:''${RESET} ''${CYAN}''${branch}''${RESET} ''${DIM}[wt: ''${wt_name}]''${RESET} ''${status_icon}"
    else
      git_section="''${BOLD}Git:''${RESET} ''${CYAN}''${branch}''${RESET} ''${status_icon}"
    fi

    git_section="''${git_section} | 📁 ''${dir_name}"
  else
    git_section="📁 ''${dir_name}"
  fi

  # === Output ===
  line1="$model_section | $ctx_section"
  if [[ -n "$rate_section" ]]; then
    line1="$line1 | $rate_section"
  fi
  printf "%s\n%s" "$line1" "$git_section"
''
