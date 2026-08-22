**Every PR opens as a draft and only leaves draft after a review cycle it did not write itself.**

The agent that wrote the code is the worst reviewer of it: it already believes the code is correct. So review is done by a fresh agent that never saw the implementation, reading only the diff and the project conventions, the way a human opens a PR cold.

The cycle, per task:

1. Implement, verify, commit, push.
2. Open the PR as a draft (`gh pr create --draft`).
3. Spawn independent reviewer subagents. They get the diff, the conventions, and the PR body. They do NOT get the implementation conversation or any justification for the code.
4. Post their merged findings as one real GitHub review with inline comments (`event: COMMENT`; GitHub rejects `APPROVE` and `REQUEST_CHANGES` on your own PR). The trail belongs on the PR, not in a chat log.
5. Triage each finding: accept, reject with a concrete reason, or ask the user. Reply in-thread, apply the accepted fixes, resolve the threads.
6. New findings and rounds left? Repeat from 3 on the new diff. Otherwise run the project's real checks and `gh pr ready`.

Rules that keep it from spinning:

- Cap at **3 rounds**. Three rounds that cannot converge need a human, not a fourth round.
- A finding already accepted-and-fixed or rejected-with-reason is settled. Never raise it again.
- Zero findings is a valid round. Never manufacture findings to look thorough.
- Never raise what the linter or formatter already enforces.
- Never mark a PR ready with an open blocker or a failing check.

A repo with no review bot is the normal case; the independent subagents are the whole mechanism. Any bot that happens to be installed is just one more reviewer in the same triage pass, never a special path.
