**Scale the review to blast radius, not to diff size. Never scale the worktree or the draft.**

Process that is disproportionate gets abandoned wholesale, which is worse than having none. So be explicit about which parts are cheap and which are not.

Cheap, therefore never skipped:

- **Worktree.** One command (`wt <branch>`). The reason it exists is concurrency safety, and that does not shrink with the task: a one-line typo fix in a shared checkout destroys a sibling agent's work exactly as thoroughly as a refactor does.
- **Draft PR.** One flag. Costs nothing to open as a draft.

Expensive, therefore tiered:

- **The reviewer fan-out.** Four to six subagents across up to three rounds is absurd for a comment typo and correct for an auth change.

### Blast radius, not line count

One line changing an authorization check is high risk. Three hundred lines rewriting docs is zero risk. Classify by what the change can break.

**Tier 1, no behavior change is possible.** Docs, comments, formatting, a lockfile bump with no code change, renaming a local that nothing outside the function can see. No reviewer at all. Run the project's real checks, and if they pass mark the PR ready.

**Tier 2, contained.** Behavior changes, but it stays inside one module: no exported signature moved, and none of the Tier 3 triggers fire. One lens, the one that matches the change, and one round.

**Tier 3, load-bearing.** Full fan-out, up to three rounds. Any one of these triggers it regardless of how small the diff is:

- a public or exported signature changed (confirm the callers with `lsp references`, do not eyeball it)
- authentication, authorization, or permissions
- a data migration, a schema change, or anything that can lose rows
- secrets, tokens, or crypto
- money, billing, or quota
- concurrency, locking, or ordering
- the error path of a request or job
- deleting a code path, or rewriting history

### Anti-gaming

The tier is a finding about the diff, not a preference about effort.

- State the tier and the evidence for it: which paths the diff touches, and whether an exported symbol moved. A tier asserted without evidence is a Tier 3.
- A Tier 3 trigger beats size every time. One line is not a reason to drop a tier.
- Uncertain between two tiers? Take the higher one.
- The user can move the tier in either direction ("just fix the typo", or "review this properly"). Their call overrides yours.
