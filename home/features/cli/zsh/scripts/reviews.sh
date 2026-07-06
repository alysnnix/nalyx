#!/usr/bin/env bash
# List all open pull requests awaiting my review
set -euo pipefail

count=$(gh search prs --review-requested=@me --state=open --json number --jq 'length')

if [ "$count" -eq 0 ]; then
  echo "No pull requests awaiting your review."
  exit 0
fi

echo "Pull requests awaiting your review ($count):"
echo

gh search prs \
  --review-requested=@me \
  --state=open \
  --json number,title,repository,author,url \
  --template '{{range .}}{{tablerow (printf "#%v" .number) .repository.nameWithOwner .title (printf "@%s" .author.login)}}{{end}}{{tablerender}}'

echo
echo "Approve with: approve <pr-number> <owner/repo>"
