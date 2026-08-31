The Anthropic account is shared with the rest of the team. Anything that reaches
claude.ai is visible to people who did not write it and cannot be recalled once
seen, so nothing from a session goes there.

`enableArtifact = false`, `autoUploadSessions = false` and `disableRemoteControl`
in the generated `settings.json` already close the surfaces the harness can
enforce. This rule covers what a setting cannot express:

- Never launch an agent with `isolation: "remote"`, and never move work into a
  cloud environment or a cloud session.
- Never offer publishing as a way to deliver something. When a result would be
  easier to read as a page, write the HTML to a local file and hand over the
  path.
- Treat "page", "share", and "link" in a request as local artifacts unless the
  ask names an external service on purpose.

Work products live in the repo, in a worktree, or on disk. A draft PR is the
only sanctioned way for output to leave this machine.
