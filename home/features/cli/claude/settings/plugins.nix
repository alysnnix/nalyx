{
  # `frontend-design@claude-plugins-official` is deliberately absent. It shipped
  # one skill and nothing else, and that skill is now pinned in
  # ../../agent-skills/sources.nix as part of the `frontend` persona, where it
  # carries `hide: true`. Kept here it would win twice over: Claude Code has no
  # way to hide a plugin skill, and in OMP the `claude-plugins` provider
  # outranks the `agents` one, so the visible copy would shadow the hidden pin
  # in both harnesses.
  enabledPlugins = {
    "code-review@claude-plugins-official" = true;
    "context7@claude-plugins-official" = true;
    "firebase@claude-plugins-official" = true;
    "impeccable@impeccable" = true;
    "playground@claude-plugins-official" = true;
    "playwright@claude-plugins-official" = true;
    "posthog@claude-plugins-official" = true;
    "pyright-lsp@claude-plugins-official" = true;
    "ralph-loop@claude-plugins-official" = true;
    "security-guidance@claude-plugins-official" = true;
    "skill-creator@claude-plugins-official" = true;
    "stripe@claude-plugins-official" = true;
    "supabase@claude-plugins-official" = true;
    "superpowers@claude-plugins-official" = true;
    "typescript-lsp@claude-plugins-official" = true;
    "vercel@claude-plugins-official" = true;
  };
}
