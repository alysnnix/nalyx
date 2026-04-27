{ pkgs, lib }:

pkgs.writeShellScriptBin "claude-statusline" ''
  JQ="${pkgs.jq}/bin/jq"
  GIT="${pkgs.git}/bin/git"
  input=$(cat)

  model=$(echo "$input" | $JQ -r '.model.display_name // "Unknown"' | sed 's/^Claude //')
  used_pct=$(echo "$input" | $JQ -r '.context_window.used_percentage // empty')
  session_id=$(echo "$input" | $JQ -r '.session_id // empty')

  RST="\033[0m"
  GRN="\033[32m"
  YLW="\033[33m"
  RED="\033[31m"
  DIM="\033[2m"
  PAC="\033[1;33m"

  # --- session reset timer ---
  # Track when a session_id was first seen; Claude's usage window is 5 hours.
  # Store start timestamps in ~/.cache/claude-sessions/<session_id>
  WINDOW_SECS=$(( 5 * 3600 ))
  reset_part=""
  if [ -n "$session_id" ]; then
    CACHE_DIR="$HOME/.cache/claude-sessions"
    mkdir -p "$CACHE_DIR"
    SESSION_FILE="$CACHE_DIR/$session_id"
    if [ ! -f "$SESSION_FILE" ]; then
      date +%s > "$SESSION_FILE"
    fi
    start_ts=$(cat "$SESSION_FILE")
    now_ts=$(date +%s)
    elapsed=$(( now_ts - start_ts ))
    remaining_secs=$(( WINDOW_SECS - elapsed ))
    if [ "$remaining_secs" -le 0 ]; then
      reset_part="''${GRN}resets now''${RST}"
    else
      hrs=$(( remaining_secs / 3600 ))
      mins=$(( (remaining_secs % 3600) / 60 ))
      if [ "$remaining_secs" -le 1800 ]; then
        TC="''${YLW}"
      else
        TC="''${DIM}"
      fi
      if [ "$hrs" -gt 0 ]; then
        reset_part="''${TC}resets in ''${hrs}h ''${mins}m''${RST}"
      else
        reset_part="''${TC}resets in ''${mins}m''${RST}"
      fi
    fi
  fi

  # --- context usage bar ---
  if [ -n "$used_pct" ]; then
    pct_int=$(printf "%.0f" "$used_pct")
    total=15
    filled=$(( pct_int * total / 100 ))
    [ "$filled" -gt "$total" ] && filled=$total
    remaining=$(( total - filled ))

    if [ "$pct_int" -ge 90 ]; then C="$RED"
    elif [ "$pct_int" -ge 70 ]; then C="$YLW"
    else C="$GRN"
    fi

    eaten=""
    for (( i = 0; i < filled; i++ )); do eaten="''${eaten}·"; done
    dots=""
    for (( i = 0; i < remaining; i++ )); do dots="''${dots}●"; done

    bar="''${DIM}''${eaten}''${RST} ''${PAC}ᗧ ''${RST}''${C}''${dots}''${RST}"
    ctx="''${bar} ''${C}''${pct_int}%''${RST}"
  else
    ctx="''${DIM}''${RST} ''${PAC}ᗧ ''${RST}''${DIM}●●●●●●●●●●●●●●● --%''${RST}"
  fi

  cost=$(echo "$input" | $JQ -r '.cost.total_cost_usd // empty')
  if [ -n "$cost" ]; then
    cost_fmt=$(printf '$%.4f' "$cost")
    price="''${DIM}''${cost_fmt}''${RST}"
  else
    price="''${DIM}\$-.----''${RST}"
  fi

  # --- git branch ---
  branch_part=""
  branch=$($GIT rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    branch_part="''${DIM} ''${RST}''${GRN}$branch''${RST}  "
  fi

  # --- account label ---
  account_label=""
  if [ -n "$CLAUDE_PROFILE" ]; then
    account_label="''${DIM}[''${RST}''${YLW}$CLAUDE_PROFILE''${RST}''${DIM}]''${RST}  "
  fi

  if [ -n "$reset_part" ]; then
    printf "%b" "''${account_label}''${branch_part}''${ctx}  ''${DIM}''${RST}$model  $price  ''${reset_part}"
  else
    printf "%b" "''${account_label}''${branch_part}''${ctx}  ''${DIM}''${RST}$model  $price"
  fi
''
