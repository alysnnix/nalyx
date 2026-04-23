---
name: deploy-coolify
description: "Use para deployar aplicacoes no Coolify via API. Ativa quando o usuario quer deployar app, fazer deploy no Coolify, subir aplicacao, publicar projeto, ou menciona Coolify, deploy.seazone.dev, ou precisa configurar build/env vars no Coolify."
user-invocable: true
---

# Deploy Coolify

> Use `/deploy-coolify` para deployar aplicacoes no Coolify (deploy.seazone.dev) via API.

## Authentication

- **Base URL:** `https://deploy.seazone.dev`
- **API Key:** `__COOLIFY_API_KEY__`

All requests use this curl pattern:

```bash
curl -s -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  -H "Content-Type: application/json" \
  "https://deploy.seazone.dev/api/v1/<endpoint>"
```

Use `jq` to parse responses.

## Pre-requisitos

| # | Informacao | Obrigatoria | Exemplo |
|---|-----------|-------------|---------|
| 1 | URL do repositorio GitHub | Sim | `https://github.com/seazone-tech/minha-app` |
| 2 | Ambiente alvo | Nao (default: production) | `production`, `staging` |
| 3 | Branch | Nao (default: `main`) | `main`, `develop` |
| 4 | Variaveis de ambiente | Nao | `VITE_API_URL=https://...` |

## Workflow

```
1. Validar acesso a API
2. Descobrir infraestrutura (servers, projects, environments)
3. Verificar se a app ja existe
4. Criar ou reconfigurar a aplicacao
5. Configurar variaveis de ambiente
6. Disparar deploy
7. Monitorar build
8. Verificar acesso
```

### 1. Validar acesso

```bash
curl -s -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  "https://deploy.seazone.dev/api/v1/servers" | jq .
```

Se retornar 401, a key esta invalida — gerar nova em **deploy.seazone.dev > Keys & Tokens > API tokens** com permissao `*`.

### 2. Descobrir infraestrutura

```bash
# Listar projetos
curl -s -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  "https://deploy.seazone.dev/api/v1/projects" | jq .

# Detalhar projeto (inclui environments)
curl -s -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  "https://deploy.seazone.dev/api/v1/projects/$PROJECT_UUID" | jq .
```

Identificar: **Project UUID**, **Environment** (production/staging), **Server UUID** (geralmente localhost).

### 3. Verificar app existente

```bash
curl -s -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  "https://deploy.seazone.dev/api/v1/applications" | jq .
```

Filtrar pelo `git_repository`. Se existir, pular para reconfigurar (4b).

### 4a. Criar aplicacao

```bash
curl -s -X POST -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  -H "Content-Type: application/json" \
  -d '{
    "project_uuid": "PROJECT_UUID",
    "server_uuid": "SERVER_UUID",
    "environment_name": "production",
    "git_repository": "ORG/REPO",
    "git_branch": "main",
    "build_pack": "nixpacks",
    "ports_exposes": "3000",
    "instant_deploy": false
  }' \
  "https://deploy.seazone.dev/api/v1/applications/private-github-app"
```

### 4b. Reconfigurar app existente

```bash
curl -s -X PATCH -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  -H "Content-Type: application/json" \
  -d '{"install_command": "bun install", "build_command": "bun run build"}' \
  "https://deploy.seazone.dev/api/v1/applications/$APP_UUID"
```

### 5. Variaveis de ambiente

```bash
curl -s -X POST -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  -H "Content-Type: application/json" \
  -d '{"key": "VITE_API_URL", "value": "https://...", "is_buildtime": true, "is_preview": false}' \
  "https://deploy.seazone.dev/api/v1/applications/$APP_UUID/envs"
```

Para apps Vite/React, vars `VITE_*` devem usar `"is_buildtime": true`.

### 6. Disparar deploy

```bash
curl -s -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  "https://deploy.seazone.dev/api/v1/deploy?uuid=$APP_UUID&force=true" | jq .
```

Retorna `deployment_uuid` para monitoramento.

### 7. Monitorar build

```bash
curl -s -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  "https://deploy.seazone.dev/api/v1/deployments/$DEPLOYMENT_UUID" | \
  jq '{status, finished_at}'
```

Status: `in_progress`, `finished`, `failed`.

### 8. Verificar acesso

```bash
curl -s -o /dev/null -w "%{http_code}" "$APP_FQDN"
```

URL padrao: `http://$APP_UUID.$SERVER_IP.sslip.io`

## Build pack detection

| Indicador | Build Pack | Porta |
|-----------|-----------|-------|
| `package.json` + `vite.config.*` | `nixpacks` | 3000 |
| `Dockerfile` | `dockerfile` | depende |
| `docker-compose.yaml` | `dockercompose` | depende |
| `package.json` + `next.config.*` | `nixpacks` | 3000 |
| `requirements.txt` / `pyproject.toml` | `nixpacks` | 8000 |
| Apenas arquivos estaticos | `static` | 80 |

## Problemas comuns

| Problema | Causa | Solucao |
|----------|-------|---------|
| `npm ci` falha com EUSAGE | `package-lock.json` desatualizado | Setar `install_command` para `bun install` ou `npm install` |
| Build muito lento (1o deploy) | Nixpacks baixando pacotes nix | Normal — builds seguintes usam cache |
| App `exited:unhealthy` | Health check falhando | Verificar porta, path do health check |
| `VITE_*` vars nao funcionam | Nao foram passadas como build-time | Usar `is_buildtime: true` |
| 404 em rotas SPA | Servidor nao redireciona para index.html | Nixpacks com Caddy resolve automaticamente |

## Rules

- **ALWAYS** validar acesso a API antes de qualquer operacao
- **ALWAYS** verificar se a app ja existe antes de criar uma nova
- **ALWAYS** usar `jq` para formatar respostas da API
- **NEVER** expor a API key no output para o usuario
- **NEVER** criar apps duplicadas sem confirmacao do usuario
- **NEVER** disparar deploy sem confirmar a configuracao com o usuario
- Se o deploy falhar, verificar logs e reportar o erro claramente
- Para apps Vite/React, sempre usar `is_buildtime: true` em vars `VITE_*`
