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
1. DBeaver resolves "sapron.localhost"
   → systemd-resolved delegates *.localhost to devproxy DNS (127.0.53.53)
   → devproxy returns 127.42.7

2. DBeaver connects to 127.42.7:5432
   → devproxy TCP forwarder → 127.0.0.1:32789 (Docker container)
```

```
Docker Socket ──→ devproxy daemon ──→ 1. Assign loopback IP (127.X.Y)
                                      2. Register in embedded DNS
                                      3. Start TCP forwarder (Go goroutines)
```

## Components

### 1. Docker Watcher (`internal/watcher/`)

- Connects to Docker socket (`/var/run/docker.sock`)
- Listens for container `start` and `die` events
- Extracts: compose project name (`com.docker.compose.project` label), exposed ports (host port → container port mappings)
- Ignores containers without exposed ports
- On `start` events, polls container inspect API until network settings are populated, with exponential backoff (500ms, 1s, 2s, 4s — capped at 4s) up to 5 attempts (7.5s total). If port mappings are not available after all attempts, logs an error and skips the container. The watcher will re-process the container if it receives subsequent events for it
- Events are serialized per project via a per-project mutex. This prevents race conditions during rapid restarts where `die` and `start` events arrive nearly simultaneously — the `start` handler waits for the `die` teardown to complete, avoiding `EADDRINUSE` on listeners
- On SIGHUP, the daemon performs a full re-scan: tears down all state and rebuilds from currently running containers. Active TCP connections are interrupted during re-scan. Useful for debugging without a full daemon restart

### 2. IP Manager (`internal/ipman/`)

- Generates deterministic IP from project name via hash
- Range: `127.10.0.0` – `127.254.254.0` (subset of `127.0.0.0/8`, ~62k unique projects)
- Adds/removes IPs on the `lo` interface via netlink (no shelling out to `ip`)
- Deterministic: same project name always maps to same IP

### 3. DNS Resolver (`internal/dns/`)

Embedded DNS server instead of editing `/etc/hosts`. This avoids the fragility of dynamic file edits — other tools (NetworkManager, systemd-resolved, VPN scripts, NixOS rebuilds) can overwrite `/etc/hosts` at any time.

- Lightweight DNS server using `github.com/miekg/dns`
- Listens on `127.0.53.53:53` (dedicated loopback IP, avoids conflict with systemd-resolved on `127.0.0.53`)
- Resolves `*.localhost` queries by looking up the project name in the in-memory state
- Returns the project's assigned loopback IP (e.g., `sapron.localhost` → `127.42.7`)
- **Bare `localhost` queries**: returns `127.0.0.1` (A) and `::1` (AAAA) — prevents breakage if nsswitch routes bare localhost through DNS instead of /etc/hosts
- Returns NXDOMAIN for unknown project names under `.localhost`
- All other queries (non-`.localhost`) are forwarded to the system's upstream DNS
- **TTL: 0 seconds** on all devproxy responses. Prevents client-side DNS caching that could cause stale resolution after container restart or IP change

The NixOS module configures systemd-resolved to delegate **only** `.localhost` queries to devproxy:

```nix
# In the NixOS module — ONLY this approach is used:
services.resolved.extraConfig = ''
  DNS=127.0.53.53
  Domains=~localhost
'';
```

This is surgical: only `*.localhost` queries go to devproxy. All other DNS traffic is unaffected. If devproxy crashes, only `.localhost` resolution breaks — the rest of the system's DNS continues working normally.

**Important**: Adding devproxy as a general nameserver (`networking.nameservers`) is NOT supported — it would route all DNS through devproxy, making it a single point of failure for the entire system. The NixOS module enforces the `Domains=~localhost` delegation approach only.

Note: `.localhost` is used instead of `.local` because `.local` is reserved for mDNS (RFC 6762). `.localhost` is guaranteed to resolve to loopback by RFC 6761.

### 4. Port Forwarder (`internal/forwarder/`)

- Pure Go TCP forwarding using `net.Listen` + `io.Copy` — no external dependencies
- One goroutine pair (read/write) per active connection, one listener per exposed port
- Listeners bind to the project's loopback IP using the **container port** (the right side of `host:container` in docker-compose). This is the "standard" port the user expects (e.g., 5432 for PostgreSQL)
- On accept, dials `127.0.0.1:<docker-host-port>` and pipes bidirectionally
- Listeners are shut down via `context.Context` cancellation when container stops
- No PID tracking needed — everything is in-process

**Multiple containers exposing the same container port:** If project "sapron" has both `postgres` (5432:5432) and `test-postgres` (5433:5432), both expose container port 5432. The first container gets `127.42.7:5432`. The second detects the conflict and falls back to the **host port**: `127.42.7:5433`. A log warning is emitted so the user knows which port was remapped.

**Half-close TCP:** The bidirectional pipe uses `TCPConn.CloseWrite()` when one side's `io.Copy` returns, signaling EOF to the other side without closing the read direction. This prevents data truncation for protocols that use half-close (e.g., HTTP/1.1 chunked). Both goroutines must complete before the connection is fully closed.

Tradeoff: socat was considered as an alternative (one process per port). Go-native forwarding was chosen because it eliminates the external runtime dependency, avoids PID lifecycle management, provides better error reporting, and scales to many ports without process overhead.

### 5. State (`internal/state/`)

- In-memory state of active projects, their IPs, ports, and listener references
- Collision map persisted to `/var/lib/devproxy/collisions.json` (see Hash Collision Handling)
- All other state is rebuilt from running containers on daemon startup

### 6. CLI (`cmd/devproxy/`)

- `devproxy daemon` — runs the daemon (normally started via systemd)
- `devproxy status` — lists active projects, IPs, and port mappings. Supports `--json` flag for machine-readable output (scripting, integration with other tools)
- `devproxy cleanup` — manually purges stale state (loopback IPs, DNS listener) without starting the daemon. Useful when the daemon crashed and the user wants to clean up before restarting

CLI commands communicate with the running daemon via Unix socket at `/run/devproxy/devproxy.sock`.

### 7. Logging

- Uses Go's `log/slog` (structured logging) throughout all components
- Default output: stderr (captured by systemd journal)
- Log levels: `INFO` for lifecycle events (project up/down), `DEBUG` for port mappings and forwarding details, `ERROR` for failures
- Each log entry includes `project`, `ip`, and `port` as structured fields. When running under systemd, these become journal fields queryable via `journalctl -u devproxy DEVPROXY_PROJECT=sapron`

## Lifecycle

### Container starts

```
docker-compose up (project: "sapron")
  → watcher detects "start" event
  → reads label com.docker.compose.project = "sapron"
  → polls container inspect for network settings (exponential backoff, capped at 4s, up to 5 attempts)
  → reads exposed ports: 5432→32789, 6379→32790
  → ipman: hash("sapron") → 127.42.7 (check collisions.json for overrides)
  → ipman: ip addr add 127.42.7/32 dev lo
  → dns: register "sapron" → 127.42.7 in memory (instant, no disk)
  → forwarder: net.Listen("tcp", "127.42.7:5432") → dial 127.0.0.1:32789
  → forwarder: net.Listen("tcp", "127.42.7:6379") → dial 127.0.0.1:32790
```

### Container stops

```
docker-compose down (project: "sapron")
  → watcher detects "die" events
  → forwarder: cancel context → listeners close, goroutines exit
  → dns: unregister "sapron" from memory
  → ipman: ip addr del 127.42.7/32 dev lo
```

### Daemon starts (recovery)

```
devproxy daemon starts
  → cleanup: purge stale state (see Resilience section)
  → load collisions.json from /var/lib/devproxy/ (if exists)
  → start embedded DNS on 127.0.53.53:53
  → start Unix socket on /run/devproxy/devproxy.sock
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
│   ├── dns/dns.go              # Embedded DNS server
│   ├── dns/dns_test.go
│   ├── forwarder/forwarder.go  # Go-native TCP forwarding
│   ├── forwarder/forwarder_test.go
│   └── state/state.go          # In-memory state + collision persistence
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

If two project names hash to the same IP, the IP Manager detects the collision (the IP is already in the active state) and applies linear probing: increment octet3, wrapping around and incrementing octet2 if needed, until a free IP is found.

The resolved collision is persisted to `/var/lib/devproxy/collisions.json`:

```json
{
  "beta": "127.42.8"
}
```

This file is only written when a collision occurs (rare). On daemon restart, the collision map is loaded first, ensuring the probed IP is stable across reboots regardless of container startup order. Projects without collisions are not stored — their IP is always derived from the hash.

## Resilience

### Cleanup on Startup

On daemon start, before scanning running containers, devproxy purges any stale state from a previous crash:

1. Remove all IPs in the `127.10.0.0` – `127.254.254.0` range from the `lo` interface via netlink scan
2. Remove the `127.0.53.53` DNS listener IP if present
3. No orphaned processes to kill — TCP forwarding and DNS are in-process (goroutines die with the daemon)

This guarantees a clean slate regardless of how the previous daemon instance exited.

### Graceful Shutdown

On SIGTERM/SIGINT the daemon runs the full teardown sequence before exiting:

1. Cancel root context → all TCP listeners, forwarding goroutines, and DNS server shut down
2. Remove all assigned loopback IPs (including 127.0.53.53)

The shutdown handler has a 5-second timeout — if cleanup hasn't finished by then, it force-exits to avoid hanging systemd. The startup cleanup handles anything missed.

### Container Restart Handling

When a container restarts, Docker may assign a new host port. The daemon handles this via the event sequence:

1. `die` event → cancel forwarder context for that container's ports (listeners close)
2. `start` event → poll for new port mappings from Docker API (exponential backoff), start new listeners

The project IP and DNS entry stay intact (same project name = same IP). Only the TCP forwarding is recycled. This means the DBeaver connection endpoint (`sapron.localhost:5432`) never changes — only the internal target port updates transparently.

## Security

- All IPs are in `127.0.0.0/8` (loopback) — never accessible from outside the machine
- No ports are opened on external interfaces
- DNS server binds to `127.0.53.53` (loopback only) — not reachable from the network
- DNS delegation is scoped to `.localhost` only — devproxy never handles general DNS, so a crash does not affect system DNS resolution
- Daemon runs as systemd service with `CAP_NET_ADMIN` (required for adding/removing loopback IPs via netlink) and `CAP_NET_BIND_SERVICE` (required for binding DNS to port 53)

## Platform Notes

### WSL2

WSL2 is the primary development environment. Tested on kernel `6.6.87.2-microsoft-standard-WSL2`:

- **Loopback IPs**: `ip addr add/del` on `lo` works correctly (verified manually). The core mechanism is confirmed functional
- **Docker socket**: May be at `/var/run/docker.sock` (Docker native in WSL) or via Docker Desktop integration. The watcher should try both paths
- **DNS**: WSL2 auto-generates `/etc/resolv.conf` pointing to the Windows DNS and does not use systemd-resolved by default. The NixOS module must handle this: either enable systemd-resolved on WSL or fall back to writing a dnsmasq-style config. This is a WSL-specific code path that must be tested

Integration tests must include WSL2 as a first-class target.

## Health Check

- `devproxy status` returns exit code 0 when the daemon is running and healthy, exit code 1 otherwise
- Communicates with the daemon via Unix socket at `/run/devproxy/devproxy.sock`
- The systemd unit includes `ExecStartPost` that verifies the daemon is responding

## Testing Strategy

### Unit Tests

- **ipman**: Hash determinism (same name → same IP), collision resolution (two names with forced collision → different IPs), collision persistence (write/read collisions.json at /var/lib/devproxy/), range boundaries (IPs always within 127.10-254.1-254)
- **dns**: DNS server responds correctly for registered names, NXDOMAIN for unknown, forwards non-.localhost queries, bare `localhost` returns 127.0.0.1/::1, TTL is 0 on all responses
- **forwarder**: Listener binds to correct IP:port, bidirectional data flow (mock TCP server), clean shutdown on context cancel, half-close handling (CloseWrite on EOF), same-project port conflict fallback to host port
- **state**: Concurrent access safety, project lifecycle (add/remove/query)

### Integration Tests

- Full lifecycle with Docker: start container → verify IP/DNS/forwarding → stop → verify cleanup
- Daemon restart recovery: create state, kill daemon, restart, verify cleanup + re-setup
- Burst scenario: start 10+ containers simultaneously, verify all get correct IPs and forwarding
- Rapid restart: stop and start container in quick succession, verify no EADDRINUSE
- WSL2: verify loopback IP management and DNS work under WSL2 networking
- Requires Docker daemon — run via `go test -tags=integration` (skipped by default)

## Nix Packaging

The `flake.nix` exports:

- `packages.x86_64-linux.default` — Go binary (statically compiled)
- `nixosModules.default` — NixOS module with systemd service + DNS delegation config

NixOS module usage:

```nix
{
  inputs.devproxy.url = "github:alysnnix/devproxy";

  # In host config:
  imports = [ inputs.devproxy.nixosModules.default ];
  services.devproxy.enable = true;
}
```

The module automatically:
- Asserts or enables `services.resolved.enable = true` (required for DNS delegation)
- Creates the systemd service with:
  - `CAP_NET_ADMIN` and `CAP_NET_BIND_SERVICE` capabilities
  - `StateDirectory=devproxy` → `/var/lib/devproxy/` for collision persistence
  - `RuntimeDirectory=devproxy` → `/run/devproxy/` for Unix socket
- Configures `services.resolved.extraConfig` with `DNS=127.0.53.53` and `Domains=~localhost`
- Adds `127.0.53.53` loopback IP on startup

## Dependencies

- Go standard library (`net`, `io`, `os`, `context`)
- `github.com/docker/docker` — Docker client SDK
- `github.com/vishvananda/netlink` — Netlink for IP management
- `github.com/miekg/dns` — Embedded DNS server
- No runtime dependencies

## Out of Scope (v1)

- Web UI / dashboard
- Multiple remote Docker hosts
- Traefik integration for HTTP routing
- Per-project custom configuration
- Podman support
- UDP port forwarding
