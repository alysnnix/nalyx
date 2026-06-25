# Design: shared `~/wrk` bidirectional sync via homelab

Date: 2026-06-25

## Goal

Make `~/wrk` a single shared folder, identical across all hosts, so work
started on one machine (e.g. laptop) can be continued on another (e.g. WSL).
The homelab is the always-on hub via Tailscale. Mental model: git-like
handoff, used sequentially (one active machine at a time).

This replaces the previous per-host backup model (PR #4), where each host
sent `~/wrk` to an isolated receive-only folder on the homelab
(`/data/sync/{desktop,laptop,wsl}`). Those folders did not see each other,
so "continue on another host" was impossible.

## Decisions

- **Topology**: one Syncthing folder `wrk` (folder id `wrk`),
  `type = sendreceive`, shared between 3 devices: `laptop`, `wsl`,
  `homelab`. Homelab is the hub. (The `desktop` host was dropped: it is the
  dormant dual-boot side of the machine that now runs as `wsl`, so it no
  longer imports the Syncthing module.)
- **Conflicts**: `maxConflicts = 0`. No `.sync-conflict-*` files. Pure
  last-writer-wins. Accepted risk: on a real conflict the losing side is
  overwritten and lost. Mitigated by sequential discipline (let sync settle
  before switching machines), not by tooling.
- **Versioning**: none. The homelab has limited storage (480 GB) and the
  user does not want history piling up.
- **Ignores**: the existing `~/wrk/.stignore` (managed by home-manager in
  `home/features/cli/zsh/default.nix`) already excludes `node_modules`,
  `.cache`, `.next`, `target`, `dist`, `__pycache__`, `.venv`, `.direnv`,
  etc. Reused as-is. Synced payload is ~20-25 GB of the 46 GB total.
- **Storage win**: the shared model stores one copy on the homelab
  (`/data/sync/wrk`), versus up to three separate copies in the old backup
  model. Net space is freed.

## Where config lives (public / private split)

- **Public** `modules/services/syncthing.nix` (imported by laptop, wsl,
  homelab): keeps `enable` + Tailscale firewall. Adds the declarative
  `wrk` folder (`sendreceive`, `maxConflicts = 0`, no versioning, devices =
  the 3 names) and sets `overrideDevices = true` / `overrideFolders = true`.
  The folder path is chosen by hostname inside the module: `/data/sync/wrk`
  on the homelab, `/home/<user>/wrk` on the work hosts. Device ids are
  declared here only as `lib.mkDefault` placeholders, so the public flake
  still evaluates without the private repo (CI / standalone).
- **Private** `nixos/syncthing.nix` (imported by `nixos/default.nix`, which
  is applied to all hosts): the real device ids, as plain assignments that
  override the public placeholders. This is the only sensitive part.
- **`hosts/homelab/default.nix`**: replaces the three backup tmpfiles dirs
  with a single `/data/sync/wrk` (the backing dir for the shared folder) and
  drops the "Receive Only" comment. The path itself is set in the module
  above, not here, to avoid a duplicate `services` attribute (statix W20).

## What is removed

- The three old receive-only backup folders are dropped from the running
  config by `overrideFolders = true`.
- Homelab tmpfiles for `/data/sync/{desktop,laptop,wsl}` become a single
  `/data/sync/wrk`.
- The private `SECURITY.md` receive-only mitigation no longer applies. It is
  updated to document the new threat model and the accepted tradeoff
  (last-writer-wins, no versioning, sequential discipline).

## Notes / explicit non-goals

- **Homelab `.stignore`**: not created. The homelab never generates
  ignorable content (it only receives), and the sending hosts already strip
  `node_modules` and caches before they ever reach the homelab. Adding it
  there would mean either duplicating the pattern list or an awkward
  cross-tree file reference, for near-zero benefit. Revisit only if builds
  ever run inside the homelab copy.
- Not git. No content merging. No auto-resolution beyond last-writer-wins.

## Rollout (operational, multi-host)

1. Device ids (collected with `syncthing device-id` on each host), now filled
   into private `nixos/syncthing.nix`:
   - wsl     = `6NTA5MR-AE73HH4-2T76BW2-XWRI4PD-O3SHM2R-YJYOKA4-OWQUR3F-PGU6HQW`
   - laptop  = `MZMQTJB-JGEVJVS-4U3ZGVO-5LOQA66-POEGET5-KGICCWX-XFGC2UO-ULF2TQV`
   - homelab = `HCXC62I-OYNNBJZ-EBWLZDI-2QX2IAJ-MTA7I4Q-Y3HPYCB-PHHBDXM-AVAGCA5`

   Each host's own id MUST match its local Syncthing cert, or it is treated
   as a remote device.
2. Rebuild homelab and WSL first (WSL is the seed source). Let WSL push the
   full `~/wrk` to the homelab and settle.
3. Bring in the laptop. Decide:
   - let it merge (union of files + last-writer-wins), or
   - move the laptop's current `~/wrk` aside first and pull a clean copy.
   The shared folder is NOT an automatic mirror of WSL: files unique to a
   host propagate up to the others.

## Verification

- `nix fmt` and `nix flake check --no-build` pass.
- Private: `nix-instantiate --parse nixos/syncthing.nix` passes.
- After rebuild: the `wrk` folder shows connected on all three devices; a test
  file created on WSL appears on the homelab and then on the laptop.
