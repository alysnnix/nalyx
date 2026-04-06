# devproxy — Automatic Docker Port Conflict Resolution

## Problem

When running multiple Docker Compose projects simultaneously (e.g., sapron-backend and reservas-backend), services like PostgreSQL and Redis bind to the same default host ports (5432, 6379), causing conflicts. Users must manually remap ports in each docker-compose.yml and remember which port belongs to which project.

## Solution

A daemon that assigns unique loopback IPs per Docker Compose project and redirects TCP traffic, allowing every project to use standard ports without conflicts.

```
sapron.localhost:5432   → sapron's PostgreSQL container
sapron.localhost:6379   → sapron's Redis container
reservas.localhost:5432 → reservas's PostgreSQL container
reservas.localhost:6379 → reservas's Redis container
```

Zero changes to existing docker-compose files. Works with any TCP protocol and any client (DBeaver, psql, redis-cli, etc.).

## Architecture

```
Docker Socket ──→ devproxy daemon ──→ 1. Assign loopback IP (127.X.Y)
                                      2. Update /etc/hosts
                                      3. Start TCP forwarder (Go goroutines)

DBeaver ──→ sapron.localhost:5432 ──→ TCP proxy ──→ container (127.0.0.1:32789)
```

## Components

### 1. Docker Watcher (`internal/watcher/`)

- Connects to Docker socket (`/var/run/docker.sock`)
- Listens for container `start` and `die` events
- Extracts: compose project name (`com.docker.compose.project` label), exposed ports (host port → container port mappings)
- Ignores containers without exposed ports
- On `start` events, retries port mapping reads up to 3 times with 500ms backoff — Docker may not have the port mapping ready immediately after the event fires

### 2. IP Manager (`internal/ipman/`)

- Generates deterministic IP from project name via hash
- Range: `127.10.0.0` – `127.254.254.0` (subset of `127.0.0.0/8`, ~62k unique projects)
- Adds/removes IPs on the `lo` interface via netlink (no shelling out to `ip`)
- Deterministic: same project name always maps to same IP

### 3. DNS Manager (`internal/dns/`)

- Adds/removes entries in `/etc/hosts`
- Format: `127.X.Y  project.localhost`
- Uses `flock(2)` (syscall.Flock with LOCK_EX) on `/etc/hosts` to prevent corruption from concurrent edits
- Managed entries are marked with a comment: `# devproxy`

Note: `.localhost` is used instead of `.local` because `.local` is reserved for mDNS (RFC 6762). On machines with Avahi enabled, `project.local` would trigger multicast DNS resolution before checking `/etc/hosts`, causing delays or failures. `.localhost` is guaranteed to resolve to loopback by RFC 6761.

### 4. Port Forwarder (`internal/forwarder/`)

- Pure Go TCP forwarding using `net.Listen` + `io.Copy` — no external dependencies
- One goroutine pair (read/write) per active connection, one listener per exposed port
- Listeners bind to the project's loopback IP: `net.Listen("tcp", "127.42.7:5432")`
- On accept, dials `127.0.0.1:<docker-host-port>` and pipes bidirectionally
- Listeners are shut down via `context.Context` cancellation when container stops
- No PID tracking needed — everything is in-process

Tradeoff: socat was considered as an alternative (one process per port). Go-native forwarding was chosen because it eliminates the external runtime dependency, avoids PID lifecycle management, provides better error reporting, and scales to many ports without process overhead.

### 5. State (`internal/state/`)

- In-memory state of active projects, their IPs, ports, and listener references
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
  → polls for exposed ports (retry up to 3x): 5432→32789, 6379→32790
  → ipman: hash("sapron") → 127.42.7
  → ipman: ip addr add 127.42.7/32 dev lo
  → dns: flock /etc/hosts, append "127.42.7 sapron.localhost  # devproxy"
  → forwarder: net.Listen("tcp", "127.42.7:5432") → dial 127.0.0.1:32789
  → forwarder: net.Listen("tcp", "127.42.7:6379") → dial 127.0.0.1:32790
```

### Container stops

```
docker-compose down (project: "sapron")
  → watcher detects "die" events
  → forwarder: cancel context → listeners close, goroutines exit
  → dns: flock /etc/hosts, remove "127.42.7 sapron.localhost  # devproxy"
  → ipman: ip addr del 127.42.7/32 dev lo
```

### Daemon starts (recovery)

```
devproxy daemon starts
  → cleanup: purge stale state (see Resilience section)
  → lists all running containers via Docker API
  → for each container with exposed ports:
    → runs the same setup as "container starts"
  → begins listening for new events
```

## Project Structure

```
devproxy/
├── cmd/devproxy/main.go        # Entrypoint: daemon or CLI subcommands
├── internal/
│   ├── watcher/watcher.go      # Docker event listener
│   ├── watcher/watcher_test.go
│   ├── ipman/ipman.go          # IP allocation via netlink
│   ├── ipman/ipman_test.go
│   ├── dns/hosts.go            # /etc/hosts management
│   ├── dns/hosts_test.go
│   ├── forwarder/forwarder.go  # Go-native TCP forwarding
│   ├── forwarder/forwarder_test.go
│   └── state/state.go          # In-memory state tracking
├── flake.nix                   # Nix package + NixOS module
├── go.mod
├── go.sum
├── LICENSE
└── README.md
```

## IP Hashing

Deterministic IP assignment from project name:

```
hash = FNV-1a(project_name)
octet2 = 10 + (hash >> 8) % 245    // range: 10-254
octet3 = 1 + hash % 254            // range: 1-254
ip = 127.{octet2}.{octet3}/32
```

This stays within `127.10.0.0` – `127.254.254.0`, avoiding `127.0.0.1` (localhost) and `127.255.x.x` (broadcast-adjacent).

### Hash Collision Handling

If two project names hash to the same IP, the IP Manager detects the collision (the IP is already in the active state) and applies linear probing: increment octet3, wrapping around and incrementing octet2 if needed, until a free IP is found. The resolved IP is stored in state so the collision mapping is stable for the lifetime of the daemon. On restart, projects are re-added in container creation order, so the first project always wins its natural hash.

## Resilience

### Cleanup on Startup

On daemon start, before scanning running containers, devproxy purges any stale state from a previous crash:

1. Remove all `/etc/hosts` lines marked with `# devproxy`
2. Remove all IPs in the `127.10.0.0` – `127.254.254.0` range from the `lo` interface via netlink scan
3. No orphaned processes to kill — TCP forwarding is in-process (goroutines die with the daemon)

This guarantees a clean slate regardless of how the previous daemon instance exited.

### Graceful Shutdown

On SIGTERM/SIGINT the daemon runs the full teardown sequence before exiting:

1. Cancel root context → all TCP listeners and forwarding goroutines shut down
2. Remove all managed `/etc/hosts` entries
3. Remove all assigned loopback IPs

The shutdown handler has a 5-second timeout — if cleanup hasn't finished by then, it force-exits to avoid hanging systemd. The startup cleanup handles anything missed.

### Container Restart Handling

When a container restarts, Docker may assign a new host port. The daemon handles this via the event sequence:

1. `die` event → cancel forwarder context for that container's ports (listeners close)
2. `start` event → poll for new port mappings from Docker API, start new listeners

The project IP and DNS entry stay intact (same project name = same IP). Only the TCP forwarding is recycled. This means the DBeaver connection endpoint (`sapron.localhost:5432`) never changes — only the internal target port updates transparently.

## Security

- All IPs are in `127.0.0.0/8` (loopback) — never accessible from outside the machine
- No ports are opened on external interfaces
- Daemon runs as systemd service with:
  - `CAP_NET_ADMIN` — required for adding/removing loopback IPs via netlink
  - Write access to `/etc/hosts` — required for DNS entries. Writes are scoped to lines marked `# devproxy`. This is broader than CAP_NET_ADMIN alone; the NixOS module grants this via `ReadWritePaths=/etc/hosts` in the systemd unit
- `/etc/hosts` edits use `flock(2)` to avoid corruption, but cannot prevent external tools (NetworkManager, systemd-resolved) from overwriting the file. In practice this is rare on NixOS since `/etc/hosts` is managed declaratively

## Testing Strategy

### Unit Tests

- **ipman**: Hash determinism (same name → same IP), collision resolution (two names with forced collision → different IPs), range boundaries (IPs always within 127.10-254.1-254)
- **dns**: Hosts file add/remove (writes correct lines, preserves non-devproxy lines), flock behavior, idempotent cleanup
- **forwarder**: Listener binds to correct IP:port, bidirectional data flow (mock TCP server), clean shutdown on context cancel
- **state**: Concurrent access safety, project lifecycle (add/remove/query)

### Integration Tests

- Full lifecycle with Docker: start container → verify IP/hosts/forwarding → stop → verify cleanup
- Daemon restart recovery: create state, kill daemon, restart, verify cleanup + re-setup
- Requires Docker daemon — run via `go test -tags=integration` (skipped by default)

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

- Go standard library (`net`, `io`, `os`, `syscall`)
- `github.com/docker/docker` — Docker client SDK
- `github.com/vishvananda/netlink` — Netlink for IP management
- No runtime dependencies (socat eliminated)

## Out of Scope (v1)

- Web UI / dashboard
- Multiple remote Docker hosts
- Traefik integration for HTTP routing
- Per-project custom configuration
- Podman support
- UDP port forwarding
