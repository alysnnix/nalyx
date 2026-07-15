{ pkgs, lib }:

pkgs.writeShellScriptBin "claude-statusline" ''
  JQ="${pkgs.jq}/bin/jq"
  GIT="${pkgs.git}/bin/git"
  input=$(cat)

  model=$(echo "$input" | $JQ -r '.model.display_name // "Unknown"' | sed 's/^Claude //')
  used_pct=$(echo "$input" | $JQ -r '.context_window.used_percentage // empty')
  sess_pct=$(echo "$input" | $JQ -r '.rate_limits.five_hour.used_percentage // empty')
  effort=$(echo "$input" | $JQ -r '.effort.level // empty')

  RST="\033[0m"
  GRN="\033[32m"
  YLW="\033[33m"
  RED="\033[31m"
  DIM="\033[2m"
  PAC="\033[1;33m"

  # --- session usage (5h window) ---
  # rate_limits.five_hour is exposed natively for Pro/Max accounts after the
  # first API response; absent otherwise.
  sess_part=""
  if [ -n "$sess_pct" ]; then
    sess_int=$(printf "%.0f" "$sess_pct")
    if [ "$sess_int" -ge 90 ]; then SC="$RED"
    elif [ "$sess_int" -ge 70 ]; then SC="$YLW"
    else SC="$GRN"
    fi
    sess_part="''${DIM}sess ''${RST}''${SC}''${sess_int}%''${RST}"
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

  # --- thinking effort ---
  effort_part=""
  if [ -n "$effort" ]; then
    effort_part="  ''${DIM}''${effort}''${RST}"
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

  if [ -n "$sess_part" ]; then
    printf "%b" "''${account_label}''${branch_part}''${ctx}  ''${DIM}''${RST}$model''${effort_part}  $price  ''${sess_part}"
  else
    printf "%b" "''${account_label}''${branch_part}''${ctx}  ''${DIM}''${RST}$model''${effort_part}  $price"
  fi
''
