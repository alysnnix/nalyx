Many agents share one machine and one SSD. A database container per task
multiplies WAL, checkpoints, image layers, and volumes by the number of agents,
and that write load is what freezes the desktop. Local services are therefore
shared, and a task isolates itself with a database name, not with a container.

## Databases and caches

- Before starting anything, look for what is already running:
  `docker ps --format '{{.Names}} {{.Image}} {{.Ports}}'`. If the project's
  Postgres (or MySQL, Redis) is up, use it.
- Isolate a worktree with its own database on that server, named
  `<project>_<worktree-slug>` (`CREATE DATABASE`, then migrate it). For Redis,
  use a separate logical db number or a key prefix. Point the worktree at it
  through its untracked `.env`, never through a committed file.
- Drop that database when the worktree is done. Never drop the project's main
  database, and never `docker compose down -v` a shared stack.
- If nothing is running, start ONE long-lived container for the project
  (`<project>-pg`, the image version the project pins) and reuse it from then
  on. Never name containers after a task, PR, or issue number.
- A dedicated container per task is allowed only when the user explicitly asks
  for it in this conversation. A migration that must start from an empty
  cluster still fits on the shared server as a fresh database.
- A throwaway server that only lives for a test run keeps its data in RAM and
  skips durability: `--tmpfs /var/lib/postgresql/data` plus
  `-c fsync=off -c synchronous_commit=off -c full_page_writes=off`. Remove it
  when the run ends.

## Apps and images

- Run the app on the host with the repo's own dev server (`pnpm dev` and the
  like). Do not `docker compose up --build` the app images just to test a
  change; build images only when the task is about the image itself.
- Stop the dev servers and containers the task started before finishing.

## Dependencies

- Install with the package manager the repo pins (`packageManager`, lockfile).
  pnpm hardlinks from one shared store, so a pnpm worktree costs almost no
  writes; `npm install` in a pnpm repo copies everything and forks the
  lockfile.
