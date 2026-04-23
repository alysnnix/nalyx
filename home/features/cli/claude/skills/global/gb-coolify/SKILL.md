---
name: gb-coolify
description: "Manage Coolify instance (deploy.seazone.dev) via API: applications, databases, services, servers, deployments, env vars, domains, logs, backups. Use when the user mentions Coolify, deploy, apps, databases, services, or deploy.seazone.dev."
user-invocable: true
---

# Coolify API

> Use `/coolify` to manage the Coolify instance at deploy.seazone.dev.

## Authentication

- **Base URL:** `https://deploy.seazone.dev/api/v1`
- **API Key:** `__COOLIFY_API_KEY__`

```bash
curl -s -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  -H "Content-Type: application/json" \
  "https://deploy.seazone.dev/api/v1/<endpoint>" | jq .
```

## Applications

### List / Get

```
GET /applications                              # list all (filterable by tag)
GET /applications/{uuid}                       # details
GET /applications/{uuid}/logs?lines=100        # runtime logs
GET /applications/{uuid}/envs                  # env vars
GET /applications/{uuid}/storages              # persistent storage
GET /applications/{uuid}/deployments           # history (skip/take pagination)
GET /applications/{uuid}/deployments/{id}      # single deployment
GET /applications/{uuid}/deployments/{id}/logs # build logs
```

### Create (by source type)

```
POST /applications/public                  # public git repo
POST /applications/private-github-app      # private repo via GitHub App
POST /applications/private-deploy-key      # private repo via SSH key
POST /applications/dockerfile              # inline Dockerfile
POST /applications/dockerimage             # pre-built image
```

Key fields: `project_uuid`, `server_uuid`, `environment_name`, `git_repository`, `git_branch`, `build_pack` (nixpacks/dockerfile/dockercompose/static), `ports_exposes`, `instant_deploy`, `name`.

### Update / Delete

```
PATCH  /applications/{uuid}    # update config (fqdn, build_command, etc.)
DELETE /applications/{uuid}    # soft-delete with async cleanup
```

### Lifecycle

```
GET|POST /applications/{uuid}/start    # deploy
GET|POST /applications/{uuid}/stop     # stop
GET|POST /applications/{uuid}/restart  # rolling restart
```

### Environment Variables

```
POST   /applications/{uuid}/envs       # create single
POST   /applications/{uuid}/envs-bulk  # create/update batch
PATCH  /applications/{uuid}/envs/{id}  # update
DELETE /applications/{uuid}/envs/{id}  # delete
```

Fields: `key`, `value`, `is_build_variable` (build-time), `is_multiline`, `is_literal`, `is_preview`.

### Persistent Storage

```
POST   /applications/{uuid}/storages              # create
GET    /applications/{uuid}/storages               # list
PATCH  /applications/{uuid}/storages/{id}          # update
DELETE /applications/{uuid}/storages/{id}          # delete
```

Fields: `source_type` (volume/bind_mount), `destination_path`, `host_path` (bind only).

## Databases

### List / Get

```
GET /databases           # list all
GET /databases/{uuid}    # details (includes backup config)
```

### Create (by type)

```
POST /databases/postgresql
POST /databases/mysql
POST /databases/mariadb
POST /databases/mongodb
POST /databases/redis
POST /databases/clickhouse
POST /databases/dragonfly
POST /databases/keydb
```

Fields: `project_uuid`, `environment_name`, `server_uuid`, `name`, `image`, `is_public` (TCP proxy for external access), resource limits (`cpu_limit`, `memory_limit`, `max_storage_size`).

### Update / Delete / Lifecycle

```
PATCH  /databases/{uuid}           # update config
DELETE /databases/{uuid}           # delete
GET|POST /databases/{uuid}/start   # start
GET|POST /databases/{uuid}/stop    # stop
GET|POST /databases/{uuid}/restart # restart
```

### Backups

```
GET    /databases/{uuid}/backups                              # list schedules
POST   /databases/{uuid}/backups                              # create schedule
PATCH  /databases/{uuid}/backups/{backup_uuid}                # update
DELETE /databases/{uuid}/backups/{backup_uuid}                # delete
GET    /databases/{uuid}/backups/{backup_uuid}/executions     # list runs
```

Fields: `cron_expression` (e.g. `"0 2 * * *"`), `retention_count`, `backup_destination_uuid`.

## Services (Docker Compose)

```
GET    /services                       # list all
GET    /services/{uuid}                # details
POST   /services                       # create (type OR docker_compose_raw)
PATCH  /services/{uuid}                # update config/compose
DELETE /services/{uuid}                # delete
GET|POST /services/{uuid}/start        # deploy
GET|POST /services/{uuid}/stop         # stop
GET|POST /services/{uuid}/restart      # restart
GET    /services/{uuid}/logs           # logs
GET    /services/{uuid}/deployments    # history
```

Fields: `type` (one-click service ID) OR `docker_compose_raw`, `project_uuid`, `server_uuid`, `environment_name`, `docker_compose_domains` (per-service domain mapping).

## Servers

```
GET    /servers                        # list all
GET    /servers/{uuid}                 # details
POST   /servers                        # add server
PATCH  /servers/{uuid}                 # update config
DELETE /servers/{uuid}                 # remove
GET|POST /servers/{uuid}/validate      # validate SSH + Docker
GET    /servers/{uuid}/resources       # list apps/dbs/services on server
GET    /servers/{uuid}/domains         # list all FQDNs for DNS config
```

Create fields: `name`, `ip`, `port`, `user`, `private_key`.

## Projects & Environments

```
GET    /projects                       # list
GET    /projects/{uuid}                # details (includes environments)
POST   /projects                       # create
PATCH  /projects/{uuid}                # update
DELETE /projects/{uuid}                # delete
GET    /environments                   # list environments
POST   /environments                   # create
PATCH  /environments/{uuid}            # update
```

## Teams

```
GET /teams                             # list user's teams
GET /teams/{id}                        # team details
GET /teams/{id}/members                # members with roles
```

Tokens are team-scoped — only access that team's resources.

## Security Keys

```
GET    /security/keys                  # list SSH keys
POST   /security/keys                  # add SSH key
DELETE /security/keys/{uuid}           # remove
```

## Deployments (direct trigger)

```
GET /deploy?uuid={app_uuid}&force=true   # trigger deploy by app UUID
```

Returns `deployment_uuid` for monitoring.

## Build Pack Detection

| Indicator | Build Pack | Default Port |
|-----------|-----------|-------------|
| `package.json` + `vite.config.*` | nixpacks | 3000 |
| `Dockerfile` | dockerfile | varies |
| `docker-compose.yaml` | dockercompose | varies |
| `package.json` + `next.config.*` | nixpacks | 3000 |
| `requirements.txt` / `pyproject.toml` | nixpacks | 8000 |
| Static files only | static | 80 |

## Status Codes

| Code | Meaning |
|------|---------|
| 200/201 | Success |
| 400 | Validation error |
| 401 | Invalid/missing token |
| 404 | Resource not found |
| 409 | Conflict (e.g. domain taken — use `force_domain_override`) |
| 422 | Unprocessable entity |
| 429 | Rate limited |

## Common Patterns

### Deploy an existing app

```bash
# Find the app
curl -s -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  "https://deploy.seazone.dev/api/v1/applications" | jq '.[] | {uuid, name, git_repository}'

# Trigger deploy
curl -s -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  "https://deploy.seazone.dev/api/v1/deploy?uuid=$APP_UUID&force=true" | jq .

# Monitor
curl -s -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  "https://deploy.seazone.dev/api/v1/applications/$APP_UUID/deployments/$DEPLOY_UUID" | jq '{status, finished_at}'
```

### Add env vars (Vite apps use is_build_variable)

```bash
curl -s -X POST -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  -H "Content-Type: application/json" \
  -d '{"key": "VITE_API_URL", "value": "https://...", "is_build_variable": true}' \
  "https://deploy.seazone.dev/api/v1/applications/$APP_UUID/envs"
```

### Create PostgreSQL database

```bash
curl -s -X POST -H "Authorization: Bearer __COOLIFY_API_KEY__" \
  -H "Content-Type: application/json" \
  -d '{"project_uuid": "...", "server_uuid": "...", "environment_name": "production", "name": "mydb", "is_public": false}' \
  "https://deploy.seazone.dev/api/v1/databases/postgresql"
```

## Rules

- **ALWAYS** use `jq` to parse and format responses
- **ALWAYS** verify the app/resource exists before creating a new one
- **ALWAYS** confirm destructive operations (delete, stop) with the user
- **NEVER** expose the API key in output
- **NEVER** create duplicate resources without explicit confirmation
- For Vite/React apps, always use `"is_build_variable": true` for `VITE_*` vars
- If deploy fails, fetch build logs and report the error clearly
- Deployment logs may expose env vars — warn the user if sharing logs
