---
name: git-workflow
description: "Git workflow para Nalyx. Use ao criar branches, fazer commits, ou preparar PRs."
user-invocable: true
---

# Git Workflow

## Branches

### Formato

```bash
type/short-description

# Exemplos
feat/add-hyprland-keybinds
fix/nvidia-driver-config
refactor/split-cli-modules
```

### Prefixos

| Prefixo | Uso |
|---------|-----|
| `feat` | Nova feature/módulo |
| `fix` | Correção de bug |
| `refactor` | Refatoração |
| `chore` | Manutenção |
| `docs` | Documentação |

### Criar Branch

```bash
git checkout main
git pull origin main
git checkout -b feat/my-feature
```

## Commits

### Formato

```
type: short description (max 72 chars)

- optional detail
- another detail
```

### Regras

- Max 50 caracteres no título
- Lowercase
- Sem ponto no final
- Modo imperativo ("add" não "added")
- **NÃO** adicionar `Co-Authored-By` nas mensagens de commit

### Exemplos

```bash
# Simples
feat: add waybar module

# Com detalhes
fix: resolve nvidia sleep issues

- add power management options
- update kernel params
```

## Antes de Commitar

### Validar

```bash
# 1. Formatar
nix fmt

# 2. Verificar
nix flake check --no-build

# 3. (Opcional) Testar rebuild
sudo nixos-rebuild dry-run --flake .#<host>
```

### Checklist

```
[ ] nix fmt executado
[ ] nix flake check passa
[ ] Commit message segue convenção
[ ] Sem secrets expostos
```

## Pull Requests

### Target

**SEMPRE** `main`

### Título

```
type: description
```

### Body

```markdown
## O que este PR faz?

- Mudança 1
- Mudança 2

## Como testar?

1. `sudo nixos-rebuild switch --flake .#<host>`
2. Verificar comportamento esperado
```

### Criar PR

```bash
gh pr create \
  --base main \
  --title "feat: add feature description" \
  --body "$(cat <<'EOF'
## O que este PR faz?

- Descrição das mudanças

## Como testar?

1. Passos de teste
EOF
)"
```
