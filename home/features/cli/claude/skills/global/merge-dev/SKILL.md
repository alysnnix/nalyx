---
name: gb-merge-dev
description: "Squash-merge the current branch's PR into develop. Rewrites title if >50 chars, adds bullet-point summary and Co-Authored-By trailer."
user-invocable: true
---

# Merge Dev

> Use `/merge-dev` to squash-merge the current PR into develop.

## Workflow

### 1. Resolve the PR

Detect the PR from the current branch:

```bash
gh pr view --json number,url,title,body,headRefName,baseRefName,state,commits
```

If no PR is found or PR is not open, inform the user and stop.

Verify the base branch is `develop`. If not, warn the user and ask for confirmation before proceeding.

### 2. Check merge readiness

```bash
gh pr checks --json name,state,conclusion
```

If there are failing required checks, warn the user and ask whether to proceed anyway.

Also check for merge conflicts:

```bash
gh pr view --json mergeable
```

If not mergeable, inform the user and stop.

### 3. Build squash commit title

Take the PR title and check if it's under 50 characters.

- If **≤50 chars:** use as-is
- If **>50 chars:** rewrite it following conventional commit format (`type: short description`) while preserving the meaning. Keep rewriting until ≤50 chars.

The title must:
- Be lowercase
- No period at end
- Imperative mood
- Follow conventional commit format

### 4. Build squash commit body

Analyze all commits in the PR to understand what was done:

```bash
gh pr view --json commits --jq '.commits[].messageHeadline'
```

Also read the PR diff for context:

```bash
gh pr diff
```

Write a body with:

```
- bullet point summarizing change 1
- bullet point summarizing change 2
- bullet point summarizing change 3

Co-Authored-By: Claude <noreply@anthropic.com>
```

Rules for the body:
- Each bullet starts with lowercase
- Imperative mood
- No fluff — describe what was done, not why
- Group related changes into a single bullet
- Max ~5 bullets (consolidate if more)

### 5. Squash and merge

```bash
gh pr merge <pr_number> \
  --squash \
  --subject "<title>" \
  --body "<body>"
```

### 6. Confirm

```bash
gh pr view <pr_number> --json state,mergeCommit
```

Report the merge commit SHA and confirm success.

## Rules

- **ALWAYS** verify the PR is open and targeting develop
- **ALWAYS** keep the squash title ≤50 characters
- **ALWAYS** add `Co-Authored-By: Claude <noreply@anthropic.com>` as the last line of the body
- **ALWAYS** use conventional commit format for the title
- **NEVER** merge without checking for failing checks first
- **NEVER** merge if the PR has conflicts — inform the user instead
- **NEVER** force merge — always use standard squash merge
