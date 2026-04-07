---
name: global-review-prs
description: "Review pending PRs assigned to you. Lists all PRs awaiting your review across repos, lets you pick which to review, then launches code-review agents."
user-invocable: true
---

# Review Pending PRs

> Use `/review-prs` to find and review all PRs waiting for your review.

## Workflow

### 1. Fetch pending reviews

Get all open PRs where the current user is requested as reviewer:
```bash
gh search prs --review-requested=@me --state=open --json repository,title,number,url,author,createdAt
```

### 2. Present the list

Display a numbered table to the user:

```
# | Repo                  | PR    | Title                          | Author      | Created
--|-----------------------|-------|--------------------------------|-------------|--------
1 | seazone-tech/wallet   | #700  | feat: add n8n webhook...       | alysnnix    | 2d ago
2 | seazone-tech/sapron   | #2680 | fix: reservation status...     | diogomene   | 5h ago
3 | other-org/other-repo  | #42   | chore: update deps             | someone     | 1w ago
```

If no PRs are found, inform the user and stop.

### 3. Ask the user

Present these options using AskUserQuestion:

- **Specific PRs:** "Which PRs do you want to review? (e.g. `1,3` or `2`)"
- **All:** "Type `all` to review every PR"
- **Cancel:** "Type `skip` to cancel"

Wait for the user's response before proceeding.

### 4. Review selected PRs

For each selected PR, execute the review using the `code-review:code-review` skill:

1. Invoke the skill: `code-review:code-review` with the PR URL as argument
2. The skill will launch specialized agents (code review, silent failure hunting, test analysis, etc.)
3. Wait for the review to complete before moving to the next PR

Use the Skill tool to invoke the review:
```
Skill: code-review:code-review
Args: <PR_URL>
```

**IMPORTANT:** Review PRs sequentially, one at a time. Do NOT launch all reviews in parallel — each review is resource-intensive and the user needs to see progress.

### 5. Summary

After all reviews are done, present a summary:

```
## Review Summary

| # | PR | Status | Key Findings |
|---|-----|--------|-------------|
| 1 | org/repo#123 | ✅ Approved | No issues found |
| 2 | org/repo#456 | ⚠️ Changes requested | 3 issues found |
```

## Rules

- **ALWAYS** fetch the latest PR list — never use cached/remembered data
- **ALWAYS** wait for user selection before starting reviews
- **ALWAYS** review PRs one at a time, showing progress between each
- **NEVER** auto-approve or auto-merge PRs
- **NEVER** start reviewing without user confirmation
- If a review fails or errors out, log it and continue with the next PR
