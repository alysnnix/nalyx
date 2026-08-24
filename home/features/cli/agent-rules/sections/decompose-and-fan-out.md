**Split every task that will produce code into slices first, then run the independent slices at the same time in subagents.**

A subagent starts with zero context. That is the point, not a limitation. It opens only the files its own slice needs and returns a result instead of a transcript, so the orchestrator's context goes on the shape of the task rather than on every file five slices had to read. A long session dies from context spent reading, not from context spent deciding.

The split is therefore not an optimization for speed. It is what keeps the orchestrator able to think at hour three.

### What the orchestrator keeps

Never delegate these. They are the whole job, and they are the cheap part:

- Reading the request and deciding what it actually means.
- The decomposition itself: naming the slices and where each one ends.
- Anything shared across slices, such as an interface, a schema, a type, or a file layout. Decide it, write it, then fan out. A prerequisite that every slice needs has nothing to run beside it.
- Taste calls, and the final judgement on whether the result answers the ask.

A subagent asked to "plan the work" is the canonical waste. It starts blank, knows less than you do, runs alone, and costs a full round trip for zero parallelism.

### What a slice gets

One batch, one subagent per slice, dispatched together. Every brief is self-contained, because zero context is also zero excuses:

- The exact files and symbols in scope, and the ones explicitly out of scope.
- The contract it must implement or consume, spelled out rather than referenced.
- The convention to follow, or the sibling file to imitate.
- How to verify its own slice: the command to run, the flow to exercise, the result expected. The slice owns its verification, and the orchestrator reads the outcome instead of re-reading the diff.

An underspecified brief does not fail slowly. It returns confident wrong code fast.

### Width is a finding, not a preference

- Fan out exactly as wide as the work decomposes. Never pad the batch with invented slices to look parallel.
- Two slices touching the same file are one slice. Concurrent edits to one file conflict.
- Sequential only when slice B cannot function without slice A's output. If the missing piece is small, run both and let B ask A for it.
- One slice is a valid answer, so state it: "one slice, serial, because X". Serial by omission is the failure. Serial with a reason is a decision.
- Spawning a single subagent and then waiting on it is doing the work yourself with extra latency and a lossy handoff. Either do it inline, or keep working on another slice while it runs.

Read-only investigation is the exception worth spending width on freely. Exploration burns context faster than anything else, and a scout hands back a summary instead of the fifty files it had to read.
