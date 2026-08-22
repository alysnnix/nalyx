---
name: gb-check-review
description: "Process review comments on a PR from any reviewer: judge each suggestion, reply in its thread, react thumbs up/down, apply accepted fixes via parallel subagents, and resolve the conversations. Actor-agnostic, works with a review bot (alfred-reviewer, coderabbit, copilot), a human reviewer, or the self review posted by /review-loop. Triggers: '/check-review', 'responde os comentarios da PR', 'processa a review'."
user-invocable: true
---

# Check Review

> Use `/check-review` to process the open review comments on a PR.
> Optional PR: `/check-review 123` or `/check-review https://github.com/org/repo/pull/123`
> Optional narrowing: `/check-review --from alfred-reviewer` or `--from coderabbitai,alysnnix`

This skill is the triage half of the review cycle. `/review-loop` calls it once per round; you can also call it standalone when a human or a bot left comments.

## Workflow

### 1. Resolve the PR

If an argument is provided (URL or number), use it directly. Otherwise detect from the current branch:

```bash
gh pr view --json number,url,headRefName,author,isDraft
```

If no PR is found, inform the user and stop. Extract `owner/repo` and `pr_number`.

### 2. Collect what is actually open

The unit of work is an **unresolved review thread**, not a login. That keeps this skill actor-agnostic and makes it idempotent: anything already handled and resolved in an earlier pass simply does not come back.

**Inline comments** - one GraphQL call gives the thread state and every field needed to reply, react, and resolve:

```bash
gh api graphql -f query='
  query($owner:String!, $repo:String!, $pr:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) {
          nodes {
            id
            isResolved
            isOutdated
            comments(first:50) {
              nodes {
                databaseId
                author { login }
                body
                path
                line
                originalLine
              }
            }
          }
        }
      }
    }
  }
' -F owner={owner} -F repo={repo} -F pr={pr_number}
```

Keep threads where `isResolved` is `false`. For each, the first comment is the suggestion; later comments are the existing discussion, read them so you do not repeat an answer already given.

**General comments** on the PR body:

```bash
gh api repos/{owner}/{repo}/issues/{pr_number}/comments --paginate
```

Keep the ones with no reply from you yet.

**Actor scope.** Default is every author in that set except your own replies. Narrow it when the caller asked: `--from <login>` keeps only those logins, matching on substring so `alfred-reviewer` also matches `alfred-reviewer[bot]`. Bot comments are recognisable by `user.type == "Bot"` (REST) or a `[bot]` suffix on `author.login` (GraphQL).

**Exclude automation bots.** dependabot, renovate, github-actions, codecov, netlify, vercel and friends comment but review nothing. Their output is status chatter, not a finding, and pulling it into triage means replying and resolving against a bot that is not asking for anything. Since they only post issue comments on the PR body and never inline, diff-anchored ones, the unresolved-thread rule in step 2 already drops them; keep it that way and do not widen the net to "any bot that commented". Read a failing-check comment for signal, then leave it alone.

Skip `isOutdated` threads whose code no longer exists, and say so in the summary.

If nothing is open, report that and stop.

### 3. Triage - judge each suggestion

For each open item:

1. **Read the real context** - open the referenced file, read the surrounding lines. Never judge from the comment text alone.
2. **Check project rules** - `CLAUDE.md`, `AGENTS.md`, lint config, and the surrounding code's own conventions.
3. **Classify**:
   - **Accept** - it is a real defect or a real improvement that matches the conventions.
   - **Reject** - wrong, already handled elsewhere, contradicts a project convention, or is a style point the linter owns.
   - **Doubtful** - genuinely needs the user's call.

A reviewer being a bot is not evidence either way. Judge the claim, not the author.

### 4. Consult the user on doubtful items

Batch them into a single question:

```
## Doubtful suggestions (need your input)

1. `src/auth.ts:42` - reviewer suggests X, current code does Y. Accept?
2. `src/api.ts:15` - reviewer suggests Z, changes behaviour. Accept?

Reply with numbers to accept (e.g. "1" or "1,2") or "none" to reject all.
```

Wait for the answer and reclassify. Do not act on a doubtful item before that.

### 5. Reply in each thread

Reply **inside the individual thread**, never one bulk comment for everything.

- **Accepted:** short - "Agreed, applying the fix."
- **Rejected:** the reason, concretely - "Skipping. `user` cannot be nil here, the caller checks it at `src/mw.ts:20`." or "Contradicts the Surgical Changes rule in CLAUDE.md."

**Inline thread reply:**
```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -f body="<reply>" \
  -F in_reply_to=<comment_databaseId>
```

**General comment:**
```bash
gh api repos/{owner}/{repo}/issues/{pr_number}/comments -f body="<reply>"
```
Quote the original when replying to a general comment, since there is no thread to anchor it.

### 6. React with emoji

On the **original** comment, not on your reply.

- Accepted: `+1`
- Rejected: `-1`

```bash
# inline
gh api repos/{owner}/{repo}/pulls/comments/{comment_databaseId}/reactions -f content="+1"
# general
gh api repos/{owner}/{repo}/issues/comments/{comment_id}/reactions -f content="+1"
```

### 7. Apply accepted suggestions (parallel subagents)

Fan out subagents to apply the accepted fixes at once. Each gets the file path, the line, the suggestion (the exact code block when GitHub's `suggestion` format was used, otherwise the described change), and enough surrounding context to place it.

**Group every suggestion touching the same file into one subagent.** Two agents editing one file race and one of the edits is lost.

If a fix fails to apply, log it in the summary and carry on with the rest. Never leave a half-applied fix in the tree.

### 8. Resolve the threads

Only after replying, reacting, and applying:

```bash
gh api graphql -f query='
  mutation($id:ID!) {
    resolveReviewThread(input:{threadId:$id}) { thread { isResolved } }
  }
' -F id=<thread_node_id>
```

Resolve rejected threads too. The reply carries the reason, and leaving them open makes the next pass re-litigate a settled point.

General issue comments have no resolve. The reply and the reaction are enough.

### 9. Summary

```
## Review check complete - PR #123

| # | Location | Suggestion | Author | Decision | Applied |
|---|---|---|---|---|---|
| 1 | src/auth.ts:42 | nil user on expired session | alfred-reviewer[bot] | accepted | yes |
| 2 | src/api.ts:15 | add null check | alysnnix | rejected, caller guarantees non-nil | - |
| 3 | src/util.ts:8 | rename variable | coderabbitai[bot] | accepted | yes |

Accepted: 2 | Rejected: 1 | Applied: 2 | Threads resolved: 3
```

## Rules

- **ALWAYS** read the real file context before judging a suggestion.
- **ALWAYS** reply inside the individual thread, never one bulk comment.
- **ALWAYS** react on the original comment.
- **ALWAYS** resolve threads after processing, accepted and rejected alike.
- **ALWAYS** ask the user about doubtful items before acting.
- **NEVER** accept a suggestion because a bot made it, and never reject one for the same reason.
- **NEVER** blindly accept the whole batch. Judge each item.
- **NEVER** apply a rejected suggestion.
- **NEVER** re-open or re-argue an already resolved thread.
- Group same-file suggestions into one subagent to avoid edit conflicts.
- Commit the applied fixes following the commit rules in `CLAUDE.md` (English, title under 50 chars, bullet body, `Co-Authored-By` trailer).
