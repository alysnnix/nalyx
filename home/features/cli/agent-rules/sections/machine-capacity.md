**This machine is shared. Before running anything parallel or heavy, measure what is free and size the work to that, never to the core count.**

Several agents run here at once, each in its own worktree, next to the desktop session, the browser, and the Paseo daemon. Every tool that defaults to "one worker per core" assumes it owns the machine. Three of them doing that at the same time is how the load average reaches 100, the disk queue fills, and the Paseo daemon stops answering its liveness check, so the user sees every agent go red at once.

## Measure first

One cheap read before the first heavy command, and again before a second one:

```bash
nproc; cat /proc/loadavg; free -h | sed -n 2p
```

- **Load average** against `nproc` is the signal. Below half the cores, there is room. Near or above the core count, the machine is already busy, so run serially or wait.
- **Available memory** (not free) under a few GiB means each extra worker risks swap, which is worse than slow.
- When the numbers say busy, see who is using the machine (`ps -eo pid,%cpu,%mem,etime,comm --sort=-%cpu | head`) before adding to it. It is often another agent's test run.

## Cap the tool, not just the subagents

Fanning out subagents is cheap; what they each run is not. Pass an explicit worker cap instead of trusting the default:

| Tool | Cap |
|---|---|
| vitest | `--maxWorkers=4` (or `--pool=threads --maxWorkers=...`) |
| jest | `--maxWorkers=4` |
| pytest-xdist | `-n 4`, never `-n auto` |
| cargo | `-j 4` |
| make | `-j4`, never a bare `-j` |
| nix build | `--max-jobs 2 --cores 4` |
| tsc, eslint, webpack | run one at a time across agents |

Four is a starting point on a quiet 20-core machine, not a constant. On a busy one, drop to one or two, or run only the tests for the files you touched.

## Clean up what you start

A command that times out or gets interrupted can leave its workers behind, reparented to PID 1 and still burning CPU. After a heavy run ends abnormally, check for orphans in your own worktree (`pgrep -af <tool>`, then confirm each `/proc/<pid>/cwd`) and stop only those. Never kill another worktree's processes without asking the user.
