**Every task that will produce commits runs in its own git worktree, and Paseo owns where worktrees live. Never work directly in the primary checkout, and never invent a path for a worktree.**

Two agents can be running in the same project at the same time. If they share a checkout, one agent's branch switch, stash, or rebase silently destroys the other's work. Worktrees give each task its own working directory over the same object store.

Paseo is the only worktree manager on this machine. It keeps every worktree under `~/.paseo/worktrees/<workspace-id>/<slug>`, tracks it, and archives it when the work is done. A worktree created by hand outside that tree is invisible to Paseo: it never shows up in the workspace list, nothing ever cleans it up, and it accumulates in `$HOME` until someone finds it months later.

Before touching any file:

1. Locate yourself: `git rev-parse --show-toplevel` and `git worktree list`.
2. If the current path is already under `~/.paseo/worktrees/`, you are in the workspace Paseo gave you. Stay there.
3. Otherwise ask Paseo for one, with `create_workspace` and `isolation: "worktree"`. Use `mode: "branch-off"` with a `branchName` for new work, or `mode: "checkout-branch"` with `branch` to pick up an existing branch. Paseo answers with the path; work there.

```
create_workspace(isolation: "worktree", mode: "branch-off",
                 path: <repo-root>, baseBranch: "main", branchName: "<branch>")
```

Only when Paseo is genuinely unreachable (no workspace tooling in this session) do you create the worktree yourself, and then it goes inside the repo:

```bash
git -C <repo-root> worktree add .worktrees/<branch> -b <branch>
cd <repo-root>/.worktrees/<branch>
```

`.worktrees/` must be gitignored. Add it before creating the worktree if it is not.

NEVER place a worktree in `$HOME`, beside the repo, or under an improvised directory such as `~/<repo>-<topic>` or `~/wrk-trees/`. "Follow the layout the project already uses" does not license a new one: a stray sibling directory from a previous session is a bug to report, not a convention to copy.

Every read, edit, build, and command for the task runs inside that worktree path. Never interleave paths between the worktree and the primary checkout.

Untracked files do not follow a worktree. Before building, copy what the project needs (`.env`, local config, credentials) and install dependencies inside the worktree.

If `git worktree add` refuses because the branch is already checked out elsewhere, another agent owns it. Do not force it. Pick a different branch or ask.

After the work is merged or abandoned, release it the same way it was created: `archive_workspace` for a Paseo workspace, and for a fallback worktree

```bash
git -C <repo-root> worktree remove .worktrees/<branch>
git -C <repo-root> worktree prune
```

No worktree needed when:
- The work is read-only: questions, code reading, investigation, review.
- The user explicitly says to work in the current checkout.
- The directory is not a git repository.

A small diff is **not** on that list. Asking Paseo for a workspace is one call, and a one-line fix corrupts a sibling agent's checkout exactly as thoroughly as a refactor does. Size never tiers the isolation.
