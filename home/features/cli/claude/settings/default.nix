{
  claude-statusline,
  claude-notify,
  claude-validate-pr,
  agent-sticky-rules,
}:
let
  plugins = import ./plugins.nix;
  mcp-servers = import ./mcp-servers.nix;
  statusline = import ./statusline.nix { inherit claude-statusline; };
  hooks = import ./hooks.nix {
    inherit claude-notify claude-validate-pr agent-sticky-rules;
  };
in
{
  claudeSettingsBase = builtins.toJSON {
    copyOnSelect = false;
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";

    # The Anthropic account is shared with the rest of the team, so anything
    # that lands on claude.ai is visible to people who are not the author.
    # Every surface that puts a page or a session there is closed below.
    #
    # enableArtifact turns the Artifact tool off outright; the deny rules are
    # the second line, because the key was already renamed once (disableArtifact
    # to enableArtifact) and ShareOnboardingGuide has no boolean of its own.
    enableArtifact = false;
    autoUploadSessions = false;
    disableRemoteControl = true;

    # Every session starts in bypass mode, so the prompts never show up.
    # skipDangerousModePermissionPrompt pre-accepts the disclaimer: without it
    # the mode is silently downgraded back to default until it is accepted once
    # in an interactive session, which also blocks `claude --bg`.
    #
    # deny rules are resolved in the same permission flow as bypass and still
    # win, so the claude.ai blocks keep applying.
    permissions = {
      defaultMode = "bypassPermissions";
      deny = [
        "Artifact"
        "ShareOnboardingGuide"
      ];
    };
    skipDangerousModePermissionPrompt = true;

    # /schedule creates cron routines that run as cloud agents.
    skillOverrides.schedule = "off";

    inherit (plugins) enabledPlugins;
    statusLine = statusline.statusLineConfig;
    hooks = hooks.hooksConfig;
    mcpServers = mcp-servers.publicMcpServers;
  };
}
