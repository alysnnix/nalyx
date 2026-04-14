---
name: gb-check-review
description: "Process alfred-reviewer bot comments on a PR: judge each suggestion, reply in threads, react with thumbs up/down, apply valid fixes via subagents, and resolve conversations."
user-invocable: true
---

# Check Review (alfred-reviewer)

> Use `/check-review` to process alfred-reviewer bot comments on a PR.
> Optionally pass a PR URL or number: `/check-review 123` or `/check-review https://github.com/org/repo/pull/123`

## Workflow

### 1. Resolve the PR

If an argument is provided (URL or number), use it directly. Otherwise detect from the current branch:

```bash
gh pr view --json number,url,headRefName
```

If no PR is found, inform the user and stop.

Extract `owner/repo` and `pr_number` from the result.

### 2. Collect alfred-reviewer comments

Fetch from both sources:

**Review comments (inline on diff):**
```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --paginate
```

**Issue comments (general on PR):**
```bash
gh api repos/{owner}/{repo}/issues/{pr_number}/comments --paginate
```

Filter both by `user.login` containing `alfred-reviewer` (handles both `alfred-reviewer` and `alfred-reviewer[bot]`).

For each comment, capture:
- `id` — for replying and reacting
- `node_id` — for resolving conversations via GraphQL
- `body` — the suggestion content
- `path` + `line` / `original_line` — file location (review comments only)
- `in_reply_to_id` — thread context

If no alfred-reviewer comments are found, inform the user and stop.

### 3. Triage — judge each suggestion

For each alfred-reviewer comment:

1. **Read the context** — open the referenced file, read surrounding lines
2. **Check project rules** — consult CLAUDE.md and project conventions to see if the suggestion aligns or contradicts
3. **Classify** into one of:
   - **Accept** — suggestion improves the code and aligns with conventions
   - **Reject** — suggestion is wrong, unnecessary, or contradicts project conventions
   - **Doubtful** — not sure, need user input

### 4. Consult user on doubtful suggestions

If there are doubtful suggestions, present them in batch using AskUserQuestion:

```
## Doubtful suggestions (need your input)

1. `src/auth.ts:42` — alfred suggests X, but current code does Y. Accept?
2. `src/api.ts:15` — alfred suggests Z, changes behavior. Accept?

Reply with numbers to accept (e.g. "1" or "1,2") or "none" to reject all.
```

Wait for user response. Reclassify based on their answer.

### 5. Respond in each thread

For each alfred-reviewer comment, reply **in its individual thread**:

- **Accepted:** short reply — "Agreed, applying fix."
- **Rejected:** reply with justification — "Skipping — [reason]. This pattern is intentional because [explanation]." or "Contradicts project convention: [rule from CLAUDE.md]."

**For review comments (inline):**
```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -f body="<reply>" \
  -f in_reply_to_id=<comment_id>
```

**For issue comments (general):**
```bash
gh api repos/{owner}/{repo}/issues/{pr_number}/comments \
  -f body="<reply>"
```
When replying to general comments, quote the original comment to make context clear.

### 6. React with emoji

On each **original** alfred-reviewer comment:

- **Accepted:** 👍
- **Rejected:** 👎

**For review comments:**
```bash
gh api repos/{owner}/{repo}/pulls/comments/{comment_id}/reactions -f content="+1"
```

**For issue comments:**
```bash
gh api repos/{owner}/{repo}/issues/comments/{comment_id}/reactions -f content="+1"
```

Replace `+1` with `-1` for rejected suggestions.

### 7. Apply accepted suggestions (parallel subagents)

Launch subagents in parallel to apply all accepted suggestions simultaneously. Each subagent receives:

- The file path and line number
- The suggestion content (code block if `suggestion` format, or text description)
- The current file content for context

For `suggestion` blocks (GitHub format), apply the exact code replacement.
For text descriptions, interpret the change and apply it.

**IMPORTANT:** Each subagent works on its own file/location. If multiple suggestions touch the same file, group them into a single subagent to avoid conflicts.

### 8. Resolve conversations

After responding, reacting, and applying, resolve each thread via GraphQL:

First, get the review thread IDs for inline comments:
```bash
gh api graphql -f query='
  query {
    repository(owner: "{owner}", name: "{repo}") {
      pullRequest(number: {pr_number}) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 1) {
              nodes {
                author { login }
              }
            }
          }
        }
      }
    }
  }
'
```

Filter threads where the first comment author is alfred-reviewer, then resolve:
```bash
gh api graphql -f query='
  mutation {
    resolveReviewThread(input: { threadId: "<thread_node_id>" }) {
      thread { isResolved }
    }
  }
'
```

For general issue comments, there is no "resolve" — the reply and reaction are sufficient.

### 9. Summary

Present a summary to the user:

```
## alfred-reviewer check complete

| # | File | Suggestion | Decision | Applied |
|---|------|-----------|----------|---------|
| 1 | src/auth.ts:42 | Use early return | ✅ Accepted | ✅ |
| 2 | src/api.ts:15 | Add null check | ❌ Rejected | — |
| 3 | src/utils.ts:8 | Rename variable | ✅ Accepted | ✅ |

Accepted: 2 | Rejected: 1 | Applied: 2
```

## Rules

- **ALWAYS** read the full context of each suggestion before judging
- **ALWAYS** reply in individual threads, never a single bulk comment
- **ALWAYS** react with emoji on the original alfred-reviewer comment
- **ALWAYS** resolve conversations after processing
- **ALWAYS** ask the user about doubtful suggestions before acting
- **NEVER** blindly accept all suggestions — judge each one
- **NEVER** skip the reaction emoji
- **NEVER** apply rejected suggestions
- Group suggestions that touch the same file into one subagent to avoid edit conflicts
- If applying a suggestion fails, log it in the summary and continue with the rest
