# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Protected Main Branch

**NEVER commit or merge to main without explicit user authorization. No exceptions.**

- NEVER run `git commit`, `git merge`, `git push`, or merge a PR targeting `main` (or `master`) unless the user explicitly authorized THAT specific action in THIS conversation.
- Authorization is NOT implied by context. "Finish this", "wrap it up", "looks good", or approving a plan does NOT authorize touching main.
- Even when the user explicitly authorizes it, you MUST confirm before executing: restate exactly what you are about to do (e.g. "This will merge PR #42 into main. Are you sure?") and wait for the user to confirm. User instructions can be ambiguous - a confirmation catches misinterpretation before it becomes irreversible.
- Only proceed after that second, unambiguous confirmation. If the answer is anything other than a clear yes, do not proceed.
- Working on feature branches, committing to them, and opening PRs remains fine - this rule protects main only.

## 6. Commit Messages

**Write commits in English, with a short title and a descriptive body.**

- ALWAYS write commit messages in English, regardless of the language used in the conversation.
- The title must not exceed 50 characters (including type and scope).
- ALWAYS include a body with descriptive bullet points explaining what changed and why.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
