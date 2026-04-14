---
name: gb-co-authored
description: "Validate that all commits in the current PR have Co-Authored-By trailer. Rewrites missing ones via interactive rebase."
user-invocable: true
---

# Co-Authored

> Use `/co-authored` to ensure all commits in the current PR have the Co-Authored-By trailer.

## Workflow

### 1. Resolve the PR and base branch

Detect the PR from the current branch:

```bash
gh pr view --json number,baseRefName,headRefName,commits
```

If no PR is found, inform the user and stop.

### 2. Identify the current user

```bash
MY_EMAIL=$(git config user.email)
MY_LOGIN=$(gh api user --jq '.login')
```

### 3. List commits in the PR (only mine)

Get all commits between the base branch and HEAD:

```bash
git log origin/<base>..HEAD --format="%H %ae %s"
```

**Only process commits authored by the current user.** Match by email (`$MY_EMAIL`) or by GitHub username (`$MY_LOGIN`). Skip all other commits — they belong to other contributors and must not be touched.

### 4. Check each of my commits for Co-Authored-By

For each of my commits, inspect the full message:

```bash
git log -1 --format="%B" <sha>
```

Check if it contains `Co-Authored-By: Claude <noreply@anthropic.com>`.

Build two lists:
- **OK:** my commits that already have the trailer
- **Missing:** my commits that need it

If all my commits are OK, inform the user and stop.

### 5. Show the user what will be rewritten

```
## Commits missing Co-Authored-By

| # | SHA | Message |
|---|-----|---------|
| 1 | abc1234 | feat: add login page |
| 2 | def5678 | fix: handle null case |

These commits will be rewritten to add the trailer. This requires a force push.
Proceed?
```

Wait for user confirmation before proceeding.

### 6. Rewrite commits

Use `git rebase` with `GIT_SEQUENCE_EDITOR` to automate the rebase. For each commit that needs the trailer, change `pick` to `reword`:

```bash
GIT_SEQUENCE_EDITOR="sed -i 's/^pick <short_sha>/reword <short_sha>/'" \
  git rebase -i origin/<base>
```

Then for each reword step, use `GIT_EDITOR` to append the trailer to the commit message. Use an env-based editor script:

```bash
# Create a temporary script that appends the trailer if missing
cat > /tmp/add-coauthor.sh << 'SCRIPT'
#!/bin/bash
if ! grep -q "Co-Authored-By: Claude" "$1"; then
  echo "" >> "$1"
  echo "Co-Authored-By: Claude <noreply@anthropic.com>" >> "$1"
fi
SCRIPT
chmod +x /tmp/add-coauthor.sh

GIT_SEQUENCE_EDITOR="sed -i -E 's/^pick (SHORT_SHAS_PIPE_SEPARATED)/reword \1/'" \
  GIT_EDITOR="/tmp/add-coauthor.sh" \
  git rebase -i origin/<base>
```

Replace `SHORT_SHAS_PIPE_SEPARATED` with the short SHAs of missing commits joined by `|` for the sed regex.

### 7. Force push

```bash
git push --force-with-lease
```

### 8. Verify

```bash
git log origin/<base>..HEAD --format="%H %s" 
```

Check all commits now have the trailer and report:

```
## Done

All N commits now have Co-Authored-By trailer.
Force pushed to origin/<branch>.
```

## Rules

- **ALWAYS** ask for user confirmation before rewriting history
- **ALWAYS** use `--force-with-lease` instead of `--force`
- **NEVER** touch commits from other authors — only rewrite the current user's commits
- **NEVER** rewrite commits that already have the trailer
- **NEVER** change anything in the commit besides appending the trailer
- **NEVER** proceed without user confirmation — this is a destructive operation
- If rebase fails (conflicts), abort with `git rebase --abort` and inform the user
