#!/usr/bin/env bash
# Approve a pull request: approve <pr-number> <repo> [message]
# <repo> can be "owner/repo" (remembered for next time) or just "repo"
# (resolved from a repo seen before).
set -euo pipefail

db="${XDG_DATA_HOME:-$HOME/.local/share}/approve/repos"

if [ "$#" -lt 2 ]; then
  echo "usage: approve <pr-number> <owner/repo | repo> [message]" >&2
  echo "example: approve 23 seazone-team/sapron-backend" >&2
  echo "         approve 23 sapron-backend   (after the repo is known)" >&2
  exit 1
fi

pr="$1"
repo_arg="$2"
shift 2
msg="${*:-}"

if [[ "$repo_arg" == */* ]]; then
  # Full owner/repo given -> remember it by its short name
  repo="$repo_arg"
  name="${repo_arg##*/}"
  mkdir -p "$(dirname "$db")"
  if [ -f "$db" ]; then
    awk -F'\t' -v n="$name" '$1 != n' "$db" >"$db.tmp" && mv "$db.tmp" "$db"
  fi
  printf '%s\t%s\n' "$name" "$repo" >>"$db"
else
  # Short name given -> resolve from the db
  repo=""
  if [ -f "$db" ]; then
    repo=$(awk -F'\t' -v n="$repo_arg" '$1 == n { print $2; exit }' "$db")
  fi
  if [ -z "$repo" ]; then
    echo "unknown repo '$repo_arg'. run once with the full owner/repo:" >&2
    echo "  approve $pr <owner>/$repo_arg" >&2
    exit 1
  fi
fi

# Show what we are about to approve
title=$(gh pr view "$pr" --repo "$repo" --json title --jq '.title')
echo "Approving #$pr on $repo:"
echo "  $title"
echo

if [ -n "$msg" ]; then
  gh pr review "$pr" --repo "$repo" --approve --body "$msg"
else
  gh pr review "$pr" --repo "$repo" --approve
fi

echo "Approved #$pr on $repo"
