---
name: global:git-workflow
description: "Git workflow instructions. Use when creating branches, making commits, or preparing pull requests."
disable-model-invocation: true
user-invocable: true
---

# Git Workflow

> Use `/git-workflow` when you need to create branches, commit, or prepare PRs.

## Branches

### Format

```bash
type/short-description

# Examples
feat/marketplace-filters
fix/discovery-credit-deduction
refactor/split-complete-profile
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

**Importante:** NÃO adicionar `Co-Authored-By` nos commits. Commits são atribuídos ao desenvolvedor.

### Rules

- Max 50 characters in title
- Lowercase
- No period at end
- Imperative mood ("add" not "added")
- Use backticks for code: `useAuth`

### Examples

```bash
# Simple
feat: add marketplace niche filter

# With details
fix: resolve credit deduction race condition

- add transaction lock in discover-influencer
- add retry logic for failed transactions
```

### Bad Examples

```bash
# Too long
feat: add the new marketplace filter component with niche selection

# Past tense
feat: Added filter

# No prefix
add filter

# With period
feat: add filter.
```

## Pull Requests

### Target

**ALWAYS** `main`

### Title

```
type: description
```

### Template

O repositório possui um template padrão em `.github/PULL_REQUEST_TEMPLATE.md` que será carregado automaticamente ao criar PRs.

O template inclui:
- Descrição das mudanças
- Tipo de mudança (feat/fix/refactor/etc)
- Domínio afetado
- Instruções de teste
- Checklists de segurança e qualidade

### Create PR

```bash
gh pr create \
  --base main \
  --title "feat: add marketplace niche filter" \
  --body "$(cat <<'EOF'
## What does this PR do?

- Adds niche filter to marketplace
- Implements searchable combobox

## How to test?

1. Access /dashboard
2. Use niche filter
3. Verify list is filtered correctly
EOF
)"
```

## Pre-Commit Checklist

```
[ ] npm run test (tests passing)
[ ] npm run lint (no errors)
[ ] Sensitive files not included (.env)
[ ] Commit message follows convention
```

## Pre-PR Checklist

```
[ ] Branch up to date with main
[ ] All commits follow convention
[ ] Clear description of changes
[ ] Test instructions included
```
