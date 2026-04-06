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

Zero changes to existing docker-compose files. Works with any TCP protocol and any client (DBeaver, psql, redis-cli, Chrome, etc.) — including Windows-native apps when running on WSL2.

## Architecture

### On Linux / inside WSL2

```
1. Client resolves "sapron.localhost"
   → systemd-resolved delegates *.localhost to devproxy DNS (127.0.53.53)
   → devproxy returns 127.42.7

2. Client connects to 127.42.7:5432
   → devproxy TCP forwarder → 127.0.0.1:32789 (Docker container)
```

### On Windows (WSL2 host)

```
1. Client resolves "sapron.localhost"
   → Windows hosts file: sapron.localhost → 10.42.7.1

2. Client connects to 10.42.7.1:5432
   → Windows loopback adapter (10.42.7.1)
   → netsh portproxy → WSL2 eth0 IP:5432
   → devproxy TCP forwarder (listening on 0.0.0.0:5432) → container
```

Same hostnames, same ports, both platforms. Setup once via `devproxy windows-setup`.

```
Docker Socket ──→ devproxy daemon ──→ 1. Assign loopback IP (127.X.Y)
                                      2. Register in embedded DNS
                                      3. Start TCP forwarder (Go goroutines)
                                      4. If WSL2: also bind on 0.0.0.0 for Windows access
```

## Components

### 1. Docker Watcher (`internal/watcher/`)

- Connects to Docker socket (`/var/run/docker.sock`). On WSL2, also tries Docker Desktop integration socket if the default is not available
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
- **AAAA queries for projects**: returns NOERROR with empty answer section (not NXDOMAIN). This prevents timeout delays from clients that query AAAA before A — they get an immediate "no IPv6 record" response and fall through to the A query
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
- On WSL2, an additional listener binds to `0.0.0.0:<same-container-port>` per project, gated by the project's loopback IP being set up. This makes the service reachable from Windows via the loopback adapter IP (see Windows Integration)
- On accept, dials `127.0.0.1:<docker-host-port>` and pipes bidirectionally
- Listeners are shut down via `context.Context` cancellation when container stops
- No PID tracking needed — everything is in-process

**Multiple containers exposing the same container port:** If project "sapron" has both `postgres` (5432:5432) and `test-postgres` (5433:5432), both expose container port 5432. The first container (alphabetically by service name) gets `127.42.7:5432`. The second falls back to the **host port**: `127.42.7:5433`. A log warning is emitted so the user knows which port was remapped. Alphabetical ordering ensures determinism across restarts.

**Half-close TCP:** The bidirectional pipe uses `TCPConn.CloseWrite()` when one side's `io.Copy` returns, signaling EOF to the other side without closing the read direction. This prevents data truncation for protocols that use half-close (e.g., HTTP/1.1 chunked). Both goroutines must complete before the connection is fully closed.

**Connection draining:** When a container stops (`die` event) or during SIGHUP re-scan, active TCP connections are severed immediately (context cancellation closes listeners and pipes). This is acceptable for a development tool — long-running queries in DBeaver will fail and need to be retried.

Tradeoff: socat was considered as an alternative (one process per port). Go-native forwarding was chosen because it eliminates the external runtime dependency, avoids PID lifecycle management, provides better error reporting, and scales to many ports without process overhead.

### 5. State (`internal/state/`)

- In-memory state of active projects, their IPs, ports, and listener references
- Collision map persisted to `/var/lib/devproxy/collisions.json` (see Hash Collision Handling)
- All other state is rebuilt from running containers on daemon startup

### 6. CLI (`cmd/devproxy/`)

- `devproxy daemon` — runs the daemon (normally started via systemd)
- `devproxy status` — lists active projects, IPs, and port mappings. Supports `--json` flag for machine-readable output (scripting, integration with other tools)
- `devproxy cleanup` — manually purges stale state (loopback IPs, DNS listener) without starting the daemon. Useful when the daemon crashed and the user wants to clean up before restarting
- `devproxy windows-setup` — generates and optionally executes a PowerShell script for Windows integration (see Windows Integration section)
- `devproxy windows-cleanup` — generates a PowerShell script to remove all Windows-side configuration

CLI commands communicate with the running daemon via Unix socket at `/run/devproxy/devproxy.sock`.

### 7. Logging

- Uses Go's `log/slog` (structured logging) throughout all components
- Default output: stderr (captured by systemd journal)
- Log levels: `INFO` for lifecycle events (project up/down), `DEBUG` for port mappings and forwarding details, `ERROR` for failures
- Each log entry includes `project`, `ip`, and `port` as structured fields. When running under systemd, these become journal fields queryable via `journalctl -u devproxy DEVPROXY_PROJECT=sapron`

## Windows Integration

Windows-native apps (DBeaver, Chrome, etc.) cannot access WSL2 loopback IPs (`127.42.7`). Windows blocks custom IPs in the `127.0.0.0/8` range on all interfaces. To provide the same `sapron.localhost:5432` experience on Windows, devproxy uses a Microsoft KM-TEST Loopback Adapter with private IPs.

### How it works

Each project gets a mirrored IP in the `10.42.0.0/16` range on Windows:

| WSL2 (127.x.y) | Windows (10.42.x.y) | Hostname |
|---|---|---|
| 127.42.7 | 10.42.7.1 | sapron.localhost |
| 127.42.8 | 10.42.8.1 | reservas.localhost |

The mapping is deterministic — same hash, different prefix.

### Setup (one-time)

`devproxy windows-setup` generates a PowerShell script (requires admin) that:

1. **Installs the Microsoft KM-TEST Loopback Adapter** — built-in Windows driver, creates a virtual network interface. No third-party software
2. **Adds IP addresses** on the loopback adapter (`10.42.7.1`, `10.42.8.1`, etc.) for each active project
3. **Creates netsh portproxy rules** that forward `10.42.7.1:5432` → `<WSL2-eth0-IP>:5432`. The WSL2 IP is auto-detected via `wsl hostname -I`
4. **Updates Windows hosts file** (`C:\Windows\System32\drivers\etc\hosts`): `10.42.7.1 sapron.localhost`

After setup, `sapron.localhost:5432` works identically in DBeaver on Windows and psql in WSL2.

### Maintenance

When containers change (new project, removed project), devproxy detects the change and:
- Outputs a notification: "Windows config outdated — run `devproxy windows-setup` to sync"
- The user re-runs `devproxy windows-setup` from WSL to update the PowerShell script

### WSL2 IP changes on reboot

The WSL2 eth0 IP changes on each Windows reboot. `devproxy windows-setup` must be re-run after reboot to update portproxy rules. The script is idempotent — it cleans up old rules before creating new ones.

Future improvement: a scheduled task on Windows that auto-updates portproxy rules on login.

### Security

- All IPs are on the Windows loopback adapter — not accessible from the network
- `netsh portproxy` rules bind to specific loopback adapter IPs, not `0.0.0.0`
- The PowerShell script requires admin (UAC prompt) — user sees exactly what will be changed
- `devproxy windows-cleanup` removes everything: adapter IPs, portproxy rules, hosts entries

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
  → if WSL2: also net.Listen("tcp", "0.0.0.0:5432") and "0.0.0.0:6379"
  → log: "sapron up — WSL2: sapron.localhost:5432, Windows: run devproxy windows-setup"
```

### Container stops

```
docker-compose down (project: "sapron")
  → watcher detects "die" events
  → forwarder: cancel context → listeners close, active connections severed, goroutines exit
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
│   ├── state/state.go          # In-memory state + collision persistence
│   └── windows/windows.go      # PowerShell script generation for Windows setup
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

WSL2 IP:    127.{octet2}.{octet3}/32
Windows IP: 10.42.{octet2}.{octet3}/32   (mirrored, same octets)
```

This stays within `127.10.0.0` – `127.254.254.0` for WSL2 and `10.42.10.0` – `10.42.254.254` for Windows, avoiding conflicts with common private networks.

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

1. `die` event → cancel forwarder context for that container's ports (listeners close, active connections severed)
2. `start` event → poll for new port mappings from Docker API (exponential backoff), start new listeners

The project IP and DNS entry stay intact (same project name = same IP). Only the TCP forwarding is recycled. This means the DBeaver connection endpoint (`sapron.localhost:5432`) never changes — only the internal target port updates transparently.

## Security

- All IPs are on loopback interfaces — never accessible from the network
  - WSL2: `127.0.0.0/8` on `lo`
  - Windows: `10.42.0.0/16` on Microsoft KM-TEST Loopback Adapter (local only, no routing)
- No ports are opened on external interfaces
- DNS server binds to `127.0.53.53` (loopback only) — not reachable from the network
- DNS delegation is scoped to `.localhost` only — devproxy never handles general DNS, so a crash does not affect system DNS resolution
- Daemon runs as systemd service with:
  - `CAP_NET_ADMIN` — required for adding/removing loopback IPs via netlink
  - `CAP_NET_BIND_SERVICE` — required for binding DNS to port 53
  - `SupplementaryGroups=docker` — required for reading `/var/run/docker.sock` without running as root
- Windows setup requires admin PowerShell (UAC prompt) — changes are visible to the user

## Platform Notes

### WSL2

WSL2 is the primary development environment. Tested on kernel `6.6.87.2-microsoft-standard-WSL2`:

- **Loopback IPs**: `ip addr add/del` on `lo` works correctly (verified manually). The core mechanism is confirmed functional
- **Windows access**: Custom loopback IPs (`127.42.x`) are NOT visible from Windows (verified). Windows integration uses the loopback adapter approach with `10.42.x.y` IPs + `netsh portproxy`
- **Docker socket**: May be at `/var/run/docker.sock` (Docker native in WSL) or via Docker Desktop integration. The watcher tries both paths
- **DNS**: WSL2 does not use systemd-resolved by default. The NixOS module must handle this: either enable systemd-resolved on WSL or configure an alternative delegation mechanism

Integration tests must include WSL2 as a first-class target.

## Health Check

- `devproxy status` returns exit code 0 when the daemon is running and healthy, exit code 1 otherwise
- Communicates with the daemon via Unix socket at `/run/devproxy/devproxy.sock`
- The systemd unit includes `ExecStartPost` that verifies the daemon is responding

## Testing Strategy

### Unit Tests

- **ipman**: Hash determinism (same name → same IP), collision resolution (two names with forced collision → different IPs), collision persistence (write/read collisions.json at /var/lib/devproxy/), range boundaries (IPs always within 127.10-254.1-254), Windows IP mirroring (127.x.y → 10.42.x.y)
- **dns**: DNS server responds correctly for registered names, NXDOMAIN for unknown, forwards non-.localhost queries, bare `localhost` returns 127.0.0.1/::1, AAAA for projects returns NOERROR with empty answer, TTL is 0 on all responses
- **forwarder**: Listener binds to correct IP:port, bidirectional data flow (mock TCP server), clean shutdown on context cancel, half-close handling (CloseWrite on EOF), same-project port conflict fallback to host port (alphabetical determinism)
- **state**: Concurrent access safety, project lifecycle (add/remove/query)
- **windows**: PowerShell script generation correctness, idempotent cleanup

### Integration Tests

- Full lifecycle with Docker: start container → verify IP/DNS/forwarding → stop → verify cleanup
- Daemon restart recovery: create state, kill daemon, restart, verify cleanup + re-setup
- Burst scenario: start 10+ containers simultaneously, verify all get correct IPs and forwarding
- Rapid restart: stop and start container in quick succession, verify no EADDRINUSE
- WSL2: verify loopback IP management, DNS, and Windows portproxy work under WSL2 networking
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
  - `SupplementaryGroups=docker` for Docker socket access
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
- Automatic Windows portproxy updates (requires Windows scheduled task — future improvement)
