---
name: gb-open-pr
description: "Open a pull request with proper conventions. Use when creating PRs: adds reviewers, labels, assignee, and follows team standards."
user-invocable: true
---

# Open Pull Request

> Use `/open-pr` to create a pull request following team conventions.

## Workflow

### 1. Pre-flight checks

```bash
# Ensure all changes are committed
git status

# Get current branch name
git branch --show-current

# Get current user
gh api user --jq '.login'

# Check remote
git remote -v
```

If there are uncommitted changes, ask the user before proceeding.

### 2. Determine base branch

**Default:** `develop`

Check if the repo has a `develop` branch:
```bash
git ls-remote --heads origin develop
```
- If `develop` exists → use `develop`
- If not → use `main`

### 3. Push branch

```bash
git push -u origin <current-branch>
```

### 4. Determine repo context

Extract `owner/repo` from the remote URL to use with `gh` commands.

### 5. Build PR metadata

#### Title
Use conventional commits format based on the branch name and changes:
```
feat: short description
fix: short description
refactor: short description
chore: short description
```

#### Body (write in Portuguese pt-BR)
```markdown
## Summary
- bullet points do que foi feito

## Alterações
- **`path/to/file.py`**: breve descrição da mudança

## Test plan
- [ ] checklist de testes necessários
```

#### Labels
Fetch **ALL** available labels in the repository:
```bash
gh api repos/{owner}/{repo}/labels --jq '.[].name'
```

Read the full list and select the labels that best describe the PR based on:
1. The type of change (feature, bugfix, refactor, etc.)
2. The domain/area affected (if there are domain-specific labels)
3. The priority or scope (if such labels exist)

Do NOT rely only on the branch prefix mapping below, it's just a fallback:
| Prefix | Label |
|--------|-------|
| `feat` | `enhancement` |
| `fix` | `bug` |
| `docs` | `documentation` |
| Other | pick best match from available labels |

You may apply multiple labels if they make sense.

#### Assignee
**ALWAYS** assign the current user as the PR owner:
```bash
CURRENT_USER=$(gh api user --jq '.login')
```
After creating the PR, verify the assignee was set correctly. If it wasn't, fix it with:
```bash
gh pr edit <PR_NUMBER> --repo {owner}/{repo} --add-assignee $CURRENT_USER
```

#### Reviewers
Find the best reviewers by analyzing recent **human** PR activity in the repo.

Bot PRs must be filtered out of the sample, not just out of the result. A repo with a large dependabot or renovate backlog will otherwise rank `dependabot[bot]` as the most active author and hand it a review request. `select(.user.type != "Bot")` is the robust discriminator; do not maintain a list of bot names.

```bash
# Most active human PR authors
gh api "repos/{owner}/{repo}/pulls?state=all&per_page=100" \
  --jq '[.[] | select(.user.type != "Bot")] | .[].user.login' | sort | uniq -c | sort -rn

# Most frequently requested human reviewers on recent human PRs
gh api "repos/{owner}/{repo}/pulls?state=closed&per_page=100" \
  --jq '[.[] | select(.user.type != "Bot")] | .[].requested_reviewers[]?
         | select(.type != "Bot") | .login' | sort | uniq -c | sort -rn
```

Select the **top 3** most relevant reviewers by combining both lists (prioritize frequent reviewers, then active contributors). Always exclude the current user.

If both lists come back empty (solo repo, or every recent PR is a bot PR), create the PR with no reviewer rather than guessing. Say so in the report.

### 6. Create PR

**ALWAYS as a draft.** A PR only leaves draft after the review cycle passes (see step 8), so humans and CI reviewers are asked to look exactly once, at code that already survived a review round.

```bash
gh pr create \
  --draft \
  --base develop \
  --title "type: description" \
  --body "..." \
  --assignee <current-user> \
  --label <labels> \
  --reviewer <reviewer1>,<reviewer2>,<reviewer3>
```

### 7. Post-creation verification

After the PR is created, verify everything was applied correctly:
```bash
gh pr view <PR_NUMBER> --repo {owner}/{repo} --json assignees,labels,reviewRequests
```

If assignee, labels, or reviewers are missing, fix them with `gh pr edit`.

### 8. Hand off to the review loop

Report the PR URL to the user, then state the next step explicitly: the PR is a draft and `/review-loop` closes it out (independent review, triage, fix, verify, `gh pr ready`).

Do not run `gh pr ready` here. Leaving draft is the review loop's decision, not this skill's.

## Rules

- **NEVER** use `main` as base if `develop` exists
- **NEVER** skip assignee or reviewers
- **NEVER** create PR with empty body
- **NEVER** guess labels, always read the full list from the repo first
- **ALWAYS** assign the current user as PR owner (assignee)
- **ALWAYS** write PR body in Portuguese (pt-BR)
- **ALWAYS** use conventional commit format for title
- **ALWAYS** verify the PR was created correctly (assignee, labels, reviewers)
- If PR template exists at `.github/PULL_REQUEST_TEMPLATE.md`, use it as body structure instead
- **ALWAYS** create the PR as a draft (`--draft`)
- **NEVER** run `gh pr ready` in this skill - only `/review-loop` marks a PR ready
- **NEVER** request a bot as a reviewer, and never let bot PRs into the reviewer-ranking sample
