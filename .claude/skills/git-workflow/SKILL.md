---
name: git-workflow
description: "Git workflow for Nalyx. Use when creating branches, making commits, or preparing PRs."
user-invocable: true
---

# Git Workflow

## Branches

### Format

```bash
type/short-description

# Examples
feat/add-hyprland-keybinds
fix/nvidia-driver-config
refactor/split-cli-modules
```

### Prefixes

| Prefix | Usage |
|--------|-------|
| `feat` | New feature/module |
| `fix` | Bug fix |
| `refactor` | Refactoring |
| `chore` | Maintenance |
| `docs` | Documentation |

### Create a Branch

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

- Max 50 characters in the title
- Lowercase
- No period at the end
- Imperative mood ("add" not "added")
- **DO NOT** add `Co-Authored-By` to commit messages

### Examples

```bash
# Simple
feat: add waybar module

# With details
fix: resolve nvidia sleep issues

- add power management options
- update kernel params
```

## Before Committing

### Validate

```bash
# 1. Format
nix fmt

# 2. Verify
nix flake check --no-build

# 3. (Optional) Test rebuild
sudo nixos-rebuild dry-run --flake .#<host>
```

### Checklist

```
[ ] nix fmt executed
[ ] nix flake check passes
[ ] Commit message follows convention
[ ] No secrets exposed
```

## Pull Requests

### Target

**ALWAYS** `main`

### Title

```
type: description
```

### Body

```markdown
## What does this PR do?

- Change 1
- Change 2

## How to test?

1. `sudo nixos-rebuild switch --flake .#<host>`
2. Verify expected behavior
```

### Create a PR

```bash
gh pr create \
  --base main \
  --title "feat: add feature description" \
  --body "$(cat <<'EOF'
## What does this PR do?

- Description of changes

## How to test?

1. Testing steps
EOF
)"
```
