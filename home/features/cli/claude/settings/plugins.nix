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
    # `false` e nao ausente: a ativacao mescla com `. * $managed`, entao uma
    # chave que some daqui sobrevive no settings.json que ja esta na maquina.
    # Apagar a linha deixaria o plugin ligado para sempre, e com ele um
    # `firebase mcp` (~305 MiB, dois processos) por agente do Paseo.
    "firebase@claude-plugins-official" = false;
    "impeccable@impeccable" = true;
    "playground@claude-plugins-official" = true;
    # Disabled, not deleted, for the same merge reason as firebase above.
    # Browser automation is standardized on agent-browser.
    "playwright@claude-plugins-official" = false;
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
