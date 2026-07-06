#!/usr/bin/env bash
# Approve a pull request: approve <pr-number> <owner/repo> [message]
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: approve <pr-number> <owner/repo> [message]" >&2
  echo "example: approve 43 goniche-team/dorinha" >&2
  exit 1
fi

pr="$1"
repo="$2"
shift 2
msg="${*:-}"

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
