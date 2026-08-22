**Every task that will produce commits runs in its own git worktree. Never work directly in the primary checkout.**

Two agents can be running in the same project at the same time. If they share a checkout, one agent's branch switch, stash, or rebase silently destroys the other's work. Worktrees give each task its own working directory over the same object store.

Before touching any file:

1. Locate yourself: `git rev-parse --show-toplevel` and `git worktree list`.
2. If the current directory is already a worktree dedicated to THIS task, stay there.
3. Otherwise create one. Default location is `<repo-root>/.worktrees/<branch>`; if `git worktree list` shows the project already keeps them elsewhere (e.g. sibling directories), follow that layout instead.

```bash
# new branch
git -C <repo-root> worktree add .worktrees/<branch> -b <branch>
# branch that already exists
git -C <repo-root> worktree add .worktrees/<branch> <branch>
cd <repo-root>/.worktrees/<branch>
```

4. `.worktrees/` must be gitignored. If it is not, add it before creating the worktree.
5. Every read, edit, build, and command for the task runs inside that worktree path. Never interleave paths between the worktree and the primary checkout.

Untracked files do not follow a worktree. Before building, copy what the project needs (`.env`, local config, credentials) and install dependencies inside the worktree.

If `git worktree add` refuses because the branch is already checked out elsewhere, another agent owns it. Do not force it. Pick a different branch or ask.

After the work is merged or abandoned:

```bash
git -C <repo-root> worktree remove .worktrees/<branch>
git -C <repo-root> worktree prune
```

No worktree needed when:
- The work is read-only: questions, code reading, investigation, review.
- The user explicitly says to work in the current checkout.
- The directory is not a git repository.

A small diff is **not** on that list. `wt <branch>` is one command, and a one-line fix corrupts a sibling agent's checkout exactly as thoroughly as a refactor does. Size tiers the review, never the isolation. See the Proportionality rule.
