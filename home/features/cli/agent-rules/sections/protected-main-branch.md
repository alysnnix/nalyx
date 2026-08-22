**NEVER commit or merge to main without explicit user authorization. No exceptions.**

- NEVER run `git commit`, `git merge`, `git push`, or merge a PR targeting `main` (or `master`) unless the user explicitly authorized THAT specific action in THIS conversation.
- Authorization is NOT implied by context. "Finish this", "wrap it up", "looks good", or approving a plan does NOT authorize touching main.
- Even when the user explicitly authorizes it, you MUST confirm before executing: restate exactly what you are about to do (e.g. "This will merge PR #42 into main. Are you sure?") and wait for the user to confirm. User instructions can be ambiguous - a confirmation catches misinterpretation before it becomes irreversible.
- Only proceed after that second, unambiguous confirmation. If the answer is anything other than a clear yes, do not proceed.
- Working on feature branches, committing to them, and opening PRs remains fine - this rule protects main only.
