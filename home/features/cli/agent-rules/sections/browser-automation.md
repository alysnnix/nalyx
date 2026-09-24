Every agent drives the browser through one tool: the `agent-browser` CLI, pinned
by Nix and already on PATH. Load its guide with `agent-browser skills get core`
before the first command.

Other browser surfaces are still reachable in some sessions, and none of them
is used unless the user names it in this conversation:

- the omp built-in `browser` object in eval (`browser.open`, `tab.*`), even
  where the harness prompt suggests it for UI verification;
- Playwright in any form (MCP, `playwright-core`, `npx playwright`).

### Chrome profiles

`agent-browser --profile <name>` reuses a local Chrome profile, logins
included. The agent then acts as the user in every account that profile holds,
so the profile is always the user's choice, never the agent's:

- NEVER open the `Default` profile. It is the personal one. Not with
  `--profile Default`, not through `AGENT_BROWSER_PROFILE`, not through a config
  file.
- NEVER use `--auto-connect` or `--cdp` against the user's own running Chrome:
  that window may be the `Default` profile.
- When a task needs a logged-in session, list the candidates with
  `agent-browser profiles`, drop `Default`, and ask the user which of the
  remaining profiles to open before running anything. Skip the question only
  when the user already named the profile in this conversation.
- Work that needs no login (localhost, a public page, a fresh test account)
  runs without `--profile`, in a clean browser, and needs no question.
- Pin the launch flags for the whole session through the environment, in the
  same shell call as the commands:
  `AGENT_BROWSER_SESSION=<name> AGENT_BROWSER_PROFILE="<profile>" AGENT_BROWSER_HEADED=1`.
  A later command without the same `--profile`/`--headed` makes the daemon
  relaunch a clean browser, and the page silently turns into `about:blank`.

### Showing the work

Save screenshots to disk and hand over the path, so the user sees what was
tested. When the user wants to watch live, run `--headed`, or point them at the
dashboard (`agent-browser dashboard start`, port 4848). Close sessions when the
task ends (`agent-browser close`), since each one holds a full Chrome.
