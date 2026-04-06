# devproxy — Automatic Docker Port Conflict Resolution

## Problem

When running multiple Docker Compose projects simultaneously (e.g., sapron-backend and reservas-backend), services like PostgreSQL and Redis bind to the same default host ports (5432, 6379), causing conflicts. Users must manually remap ports in each docker-compose.yml and remember which port belongs to which project.

## Solution

A daemon that assigns unique loopback IPs per Docker Compose project and redirects TCP traffic, allowing every project to use standard ports without conflicts.

```
sapron.local:5432   → sapron's PostgreSQL container
sapron.local:6379   → sapron's Redis container
reservas.local:5432 → reservas's PostgreSQL container
reservas.local:6379 → reservas's Redis container
```

Zero changes to existing docker-compose files. Works with any TCP protocol and any client (DBeaver, psql, redis-cli, etc.).

## Architecture

```
Docker Socket ──→ devproxy daemon ──→ 1. Assign loopback IP (127.0.10.X)
                                      2. Update /etc/hosts
                                      3. Spawn socat per exposed port

DBeaver ──→ sapron.local:5432 ──→ socat ──→ container (127.0.0.1:32789)
```

## Components

### 1. Docker Watcher (`internal/watcher/`)

- Connects to Docker socket (`/var/run/docker.sock`)
- Listens for container `start` and `die` events
- Extracts: compose project name (`com.docker.compose.project` label), exposed ports (host port → container port mappings)
- Ignores containers without exposed ports

### 2. IP Manager (`internal/ipman/`)

- Generates deterministic IP from project name via hash
- Range: `127.0.10.0/16` (~65k unique projects)
- Adds/removes IPs on the `lo` interface via netlink (no shelling out to `ip`)
- Deterministic: same project name always maps to same IP

### 3. DNS Manager (`internal/dns/`)

- Adds/removes entries in `/etc/hosts`
- Format: `127.0.10.X  project.local`
- Uses file locking to prevent corruption from concurrent edits
- Managed entries are marked with a comment: `# devproxy`

### 4. Port Forwarder (`internal/forwarder/`)

- Spawns one socat process per exposed port
- Command: `socat TCP-LISTEN:<original-port>,bind=<project-ip>,fork,reuseaddr TCP:127.0.0.1:<docker-host-port>`
- Kills socat processes when container stops
- Tracks PIDs for cleanup

### 5. State (`internal/state/`)

- In-memory state of active projects, their IPs, ports, and socat PIDs
- No persistent storage needed — state is rebuilt from running containers on daemon startup

### 6. CLI (`cmd/devproxy/`)

- `devproxy daemon` — runs the daemon (normally started via systemd)
- `devproxy status` — lists active projects, IPs, and port mappings
- `devproxy logs` — shows daemon logs (or directs to journalctl)

## Lifecycle

### Container starts

```
docker-compose up (project: "sapron")
  → watcher detects "start" event
  → reads label com.docker.compose.project = "sapron"
  → reads exposed ports: 5432→32789, 6379→32790
  → ipman: hash("sapron") → 127.0.10.42
  → ipman: ip addr add 127.0.10.42/32 dev lo
  → dns: append "127.0.10.42 sapron.local  # devproxy" to /etc/hosts
  → forwarder: socat TCP-LISTEN:5432,bind=127.0.10.42,fork TCP:127.0.0.1:32789
  → forwarder: socat TCP-LISTEN:6379,bind=127.0.10.42,fork TCP:127.0.0.1:32790
```

### Container stops

```
docker-compose down (project: "sapron")
  → watcher detects "die" events
  → forwarder: kill socat processes (PIDs tracked)
  → dns: remove "127.0.10.42 sapron.local  # devproxy" from /etc/hosts
  → ipman: ip addr del 127.0.10.42/32 dev lo
```

### Daemon starts (recovery)

```
devproxy daemon starts
  → lists all running containers via Docker API
  → for each container with exposed ports:
    → runs the same setup as "container starts"
  → begins listening for new events
```

## Project Structure

```
devproxy/
├── cmd/devproxy/main.go       # Entrypoint: daemon or CLI subcommands
├── internal/
│   ├── watcher/watcher.go     # Docker event listener
│   ├── ipman/ipman.go         # IP allocation via netlink
│   ├── dns/hosts.go           # /etc/hosts management
│   ├── forwarder/forwarder.go # socat process management
│   └── state/state.go         # In-memory state tracking
├── flake.nix                  # Nix package + NixOS module
├── go.mod
├── go.sum
├── LICENSE
└── README.md
```

## IP Hashing

Deterministic IP assignment from project name:

```
hash = FNV-1a(project_name)
octet3 = 10 + (hash >> 8) % 246    // range: 10-255
octet4 = 1 + hash % 254            // range: 1-254
ip = 127.{octet3}.{octet4}/32
```

This avoids `127.0.0.1` (localhost) and provides consistent mapping.

## Security

- All IPs are in `127.0.0.0/8` (loopback) — never accessible from outside the machine
- No ports are opened on external interfaces
- Daemon runs as systemd service with `CAP_NET_ADMIN` capability (required for loopback IP management) — not full root
- `/etc/hosts` writes are scoped to lines marked with `# devproxy` comment

## Nix Packaging

The `flake.nix` exports:

- `packages.x86_64-linux.default` — Go binary (statically compiled)
- `nixosModules.default` — NixOS module with systemd service

NixOS module usage:

```nix
{
  inputs.devproxy.url = "github:alysnnix/devproxy";

  # In host config:
  imports = [ inputs.devproxy.nixosModules.default ];
  services.devproxy.enable = true;
}
```

## Dependencies

- Go standard library
- `github.com/docker/docker` — Docker client SDK
- `github.com/vishvananda/netlink` — Netlink for IP management
- `socat` — Runtime dependency (Nix package)

## Out of Scope (v1)

- Web UI / dashboard
- Multiple remote Docker hosts
- Traefik integration for HTTP routing
- Per-project custom configuration
- Podman support
- UDP port forwarding
