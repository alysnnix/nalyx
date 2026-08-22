---
name: gb-review-loop
description: "Closed-loop self review on a draft PR. Spawns independent reviewer subagents that never saw the implementation, posts their findings as a real GitHub review with inline comments, triages and fixes them, then repeats until clean and marks the PR ready. Project-agnostic: works with no bot at all, and folds in any reviewer bot present (alfred-reviewer, coderabbit, copilot). Triggers: '/review-loop', 'roda o loop de review', 'revisa a PR', 'fecha o ciclo de review'."
user-invocable: true
---

# Review Loop

> Use `/review-loop` to run the review cycle on a draft PR until it is ready.
> Optionally pass a PR: `/review-loop 123` or `/review-loop https://github.com/org/repo/pull/123`

The loop exists because the agent that wrote the code is the worst possible reviewer of it: it already believes the code is correct. So the reviewer is a **fresh subagent that never saw the implementation conversation**. It only sees the diff and the project conventions, exactly like a human opening the PR cold.

```
implement -> draft PR -> review (independent agents + any bots)
                             |
                             v
                    triage -> fix -> push
                             |
                    new findings? --yes--> next round (max 3)
                             |
                             no
                             v
                      verify -> gh pr ready
```

## Preconditions

1. The PR exists and is a **draft**. Check:
   ```bash
   gh pr view --json number,url,isDraft,headRefName,headRefOid,baseRefName,title,body
   ```
   - No PR: stop and tell the user to run `/open-pr` first.
   - Not a draft: ask before continuing. The loop is meant to run before humans are asked to look.
2. The working tree is clean and pushed. Uncommitted work is not in the diff the reviewer sees, so it would be reviewed blind.
3. You are in the task's worktree (see the One Worktree Per Task rule in `CLAUDE.md`). Never run the loop from the primary checkout while another agent holds the branch.

Extract `owner/repo`, `pr_number`, and `head_sha` (`headRefOid`) and carry them through every round.

## State carried across rounds

Keep these in your context for the whole loop. They are what stops it from spinning.

| Variable | Meaning |
|---|---|
| `ROUND` | current round, starts at 1 |
| `MAX_ROUNDS` | hard cap, **3** |
| `REVIEWED_SHA` | last commit already reviewed; round 1 = the merge base |
| `ADJUDICATED` | every finding already accepted-and-fixed or rejected-with-reason, as `path:line - one line claim` |

`ADJUDICATED` is the memory of the loop. A finding in that list is settled and MUST NOT be raised again by any later round.

## Round

### 1. Build the review surface

```bash
# full diff for round 1, delta only for later rounds
git diff <REVIEWED_SHA>...HEAD
git diff --name-only <REVIEWED_SHA>...HEAD
```

Also collect, once:
- `CLAUDE.md` / `AGENTS.md` and any project docs on conventions.
- Lint and format config (`eslint.config.*`, `ruff.toml`, `.editorconfig`, `treefmt.toml`). Whatever the linter already enforces is **not** a review finding.
- The project's test and build commands (`package.json` scripts, `Makefile`, `justfile`, `flake.nix` checks).

### 2. Spawn the reviewers in parallel

One batch, one subagent per lens. Fan out only the lenses that the diff actually touches.

| Lens | Looks for | Agent |
|---|---|---|
| Correctness | wrong logic, off-by-one, unhandled nil/empty, broken invariant, race | `reviewer` |
| Error handling | swallowed error, empty catch, fallback that hides the failure, wrong error path | `silent-failure-hunter` |
| Interface | breaking change to a public signature, caller not updated, dead code left behind, leaked abstraction | `type-design-analyzer` |
| Security and data | injection, missing authz check, secret in code, unbounded query, destructive migration with no rollback | `reviewer` |
| Tests | new behavior with no test, test that cannot fail, test coupled to implementation detail | `pr-test-analyzer` |
| Conventions | diverges from the surrounding code's own patterns, adds a second convention beside an existing one | `code-reviewer` |

Match the lens to the agent that is actually built for it. `silent-failure-hunter` exists specifically for swallowed errors and misleading fallbacks, which is why error handling is its own lens rather than a bullet under correctness. `comment-analyzer` is also available when a diff carries substantial new doc comments.

Correctness and security both map to `reviewer`. On a small diff, give one `reviewer` invocation both briefs instead of spawning it twice against the same code.

These are omp harness specialist agents. This skill also runs under Claude Code, where they do not exist. So for every lens: spawn the named agent when the harness provides it, otherwise spawn a generic subagent briefed with that lens's "Looks for" column instead. A missing named agent must never abort the loop, just fall back for that lens and keep going.

Each reviewer subagent gets:
- The diff and the list of changed files.
- The project conventions and the lint config.
- The PR title and body (the stated intent, so it can catch intent-vs-code mismatch).
- `ADJUDICATED`, labelled **already settled, do not raise again**.

Each reviewer subagent MUST NOT get:
- This conversation, the implementation plan, or any justification for the code. It reviews the diff cold, whether it is the named agent or a generic fallback.

Instruct every reviewer:
- Return findings only. **Do not post anything to GitHub.** The orchestrator posts.
- Every finding needs `path`, `line` (a line that exists in the diff), a severity, and a concrete failure mode: the input or sequence that breaks. "Could be cleaner" is not a finding.
- Severity is one of `blocker`, `major`, `minor`.
- Finding nothing is a valid and expected answer. Do not manufacture findings to look useful.

### 3. Dedupe and post one review

Merge the findings from every reviewer. Two findings are the same when they share `path:line` and make the same claim; keep the clearest wording and the highest severity. Drop anything already in `ADJUDICATED`.

If zero findings remain, skip to step 6.

Post **one** review, not one per reviewer. The nested `comments` array cannot be sent with `-f`, so build a JSON file and pipe it:

```bash
cat > /tmp/review-$$.json <<'EOF'
{
  "commit_id": "<head_sha>",
  "event": "COMMENT",
  "body": "Automated review, round <ROUND>. <n> findings: <b> blocker, <m> major, <k> minor.",
  "comments": [
    { "path": "src/auth.ts", "line": 42, "side": "RIGHT", "body": "**blocker** - `user` is nil when the session expired mid-request, so `.id` panics. Reached by <concrete path>." }
  ]
}
EOF
gh api --method POST repos/{owner}/{repo}/pulls/{pr_number}/reviews --input /tmp/review-$$.json
```

Notes that will bite otherwise:
- `event` MUST be `COMMENT`. GitHub rejects `APPROVE` and `REQUEST_CHANGES` on your own PR with 422.
- `line` must be a line present in the diff on the `RIGHT` side, otherwise the whole review 422s. For a range use `start_line` plus `line`.
- If the POST fails, retry once posting the findings as a single issue comment via `gh pr comment` rather than losing them.

### 4. Fold in the reviewer bots

External reviewer bots run on their own clock. Give them a bounded window before triage so their comments land in the same round.

**Not every bot is a reviewer.** Most repos are full of automation that comments but reviews nothing: dependabot, renovate, github-actions, codecov, netlify, vercel. Treating those as reviewers drags CI chatter into triage as if it were a finding.

The discriminator is behavioural, not a name list: a **reviewer** bot posts inline comments anchored to a line of the diff, so it appears in `/pulls/{n}/comments` with a `path`. Automation only posts issue comments on the PR body.

```bash
# reviewer bots on THIS pr: bots with at least one inline, diff-anchored comment
for i in $(seq 1 10); do
  gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --paginate \
    --jq '[.[] | select(.user.type == "Bot") | select(.path != null) | .user.login] | unique'
  sleep 30
done
```

Stop early once that set stops growing. Do not wait past five minutes: a bot that is not configured for this repo will never answer, and that is fine. A repo with no reviewer bot at all is the normal case, and the loop must work end to end without one.

Bot issue comments are informational. Read them for signal (a failing check is worth knowing about) but do not enter them into triage as review findings, and never reply-and-resolve against them.

### 5. Triage, fix, reply, resolve

Hand the comment set to the **`gb-check-review`** skill, scoped to this round's actors: your own review plus the reviewer bots identified above. That skill owns judging each comment, replying in-thread, reacting, applying accepted fixes via subagents, and resolving threads. Do not reimplement it here.

Then, for every comment it processed, append to `ADJUDICATED`.

If any fix was applied:
```bash
git add -A && git commit -m "fix: address review round <ROUND>" && git push
```
Follow the commit rules in `CLAUDE.md` (English, title under 50 chars, body with bullets, `Co-Authored-By` trailer).

### 6. Loop or exit

Set `REVIEWED_SHA` to the SHA that was just reviewed, refresh `head_sha`, and decide:

- Open `blocker` or `major` remaining, and `ROUND < MAX_ROUNDS`: `ROUND++`, go to step 1. The next round reviews only the delta plus a re-check of what was just fixed.
- Nothing open above `minor`: go to step 7.
- `ROUND == MAX_ROUNDS` with something still open: **stop**. Do not mark ready. Report what is still open and hand it to the user. Three rounds that cannot converge means the disagreement needs a human, not a fourth round.

### 7. Verify, then mark ready

Run the project's real checks, not a narrowed subset:

```bash
# whatever the project actually uses
npm test && npm run build     # or
pytest && ruff check .        # or
nix flake check --no-build
```

A failing check blocks readiness. Fix it and run one more round.

Then, and only then:
```bash
gh pr ready {pr_number}
```

### 8. Report

```
## Review loop complete - PR #123

Rounds: 2 | Reviewers: correctness, tests | Bots: alfred-reviewer

| Round | Finding | Severity | Decision | Applied |
|---|---|---|---|---|
| 1 | src/auth.ts:42 nil user on expired session | blocker | accepted | yes |
| 1 | src/api.ts:15 missing test for 429 retry | major | accepted | yes |
| 1 | src/util.ts:8 rename helper | minor | rejected, matches existing naming | - |
| 2 | none | - | - | - |

Verification: npm test + npm run build passed
Status: marked ready for review
```

## Rules

- **ALWAYS** run the reviewer as a fresh subagent with no access to the implementation rationale. A reviewer that knows why the code was written that way is not a reviewer.
- **ALWAYS** post findings as a real GitHub review with inline comments, so the trail lives on the PR and not in a chat log.
- **ALWAYS** post one merged review per round, never one per reviewer subagent.
- **ALWAYS** carry `ADJUDICATED` forward and forbid re-raising settled findings.
- **ALWAYS** run the project's verification before `gh pr ready`.
- **NEVER** exceed `MAX_ROUNDS` (3). Hand unconverged disagreement to the user.
- **NEVER** use `event: APPROVE` or `REQUEST_CHANGES` on your own PR. GitHub returns 422.
- **NEVER** mark a PR ready with an open `blocker` or `major`, or with a failing check.
- **NEVER** let a reviewer invent findings to justify itself. Zero findings is a valid round.
- **NEVER** raise what the linter or formatter already enforces.
- A repo with no reviewer bot is the normal case. The loop must work end to end with the independent subagents alone.
- **NEVER** treat every `user.type == "Bot"` as a reviewer. Only bots with inline, diff-anchored comments on this PR are reviewers; dependabot, renovate, github-actions and friends are automation noise.
- **ALWAYS** use the named agent for a lens when the harness provides it (`silent-failure-hunter`, `type-design-analyzer`, `reviewer`, `pr-test-analyzer`); fall back to a generic subagent briefed with the same lens when it does not. A missing agent is never a reason to skip a lens or abort the loop.
