---
name: git-workflow
description: "Git workflow instructions. Use when creating branches, making commits, or preparing pull requests."
user-invocable: true
---

# Git Workflow

## Branches

### Format

```bash
type/short-description

# Examples
feat/marketplace-filters
fix/auth-token-refresh
refactor/split-components
```

### Prefixes

| Prefix | Use |
|--------|-----|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Refactoring |
| `chore` | Maintenance |
| `docs` | Documentation |
| `test` | Tests |
| `perf` | Performance |

### Create Branch

```bash
git checkout main
git pull origin main
git checkout -b feat/my-feature
```

## Commits

### Format

```
type: short description (max 72 chars)

- optional detail
- another detail
```

### Rules

- Max 50 characters in title
- Lowercase
- No period at end
- Imperative mood ("add" not "added")
- Use backticks for code references
- **DO NOT** add `Co-Authored-By` in commit messages

### Examples

```bash
# Simple
feat: add user authentication

# With details
fix: resolve race condition in data fetching

- add mutex lock
- add retry logic
```

### Bad Examples

```bash
# Too long
feat: add the new component with all the features and options

# Past tense
feat: Added filter

# No prefix
add filter

# With period
feat: add filter.
```

## Pull Requests

### Target

**ALWAYS** `main` (unless specified otherwise)

### Title

```
type: description
```

### Body Template

```markdown
## What does this PR do?

- Change 1
- Change 2

## How to test?

1. Step 1
2. Step 2
3. Verify expected behavior
```

### Create PR

```bash
gh pr create \
  --base main \
  --title "feat: add feature description" \
  --body "$(cat <<'EOF'
## What does this PR do?

- Description of changes

## How to test?

1. Test steps
EOF
)"
```

## Pre-Commit Checklist

```
[ ] Tests passing
[ ] Linting passing
[ ] No sensitive files (.env, credentials)
[ ] Commit message follows convention
```

## Pre-PR Checklist

```
[ ] Branch up to date with main
[ ] All commits follow convention
[ ] Clear description of changes
[ ] Test instructions included
```
