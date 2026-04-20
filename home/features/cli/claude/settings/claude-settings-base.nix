{
  lib,
  privateMcpConfig,
  claudeStatusline,
  claudeNotify,
}:

builtins.toJSON {
  enabledPlugins = {
    "code-review@claude-plugins-official" = true;
    "context7@claude-plugins-official" = true;
    "firebase@claude-plugins-official" = true;
    "frontend-design@claude-plugins-official" = true;
    "playground@claude-plugins-official" = true;
    "playwright@claude-plugins-official" = true;
    "posthog@claude-plugins-official" = true;
    "pr-review-toolkit@claude-plugins-official" = true;
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
  statusLine = {
    type = "command";
    command = "${claudeStatusline}/bin/claude-statusline";
  };
  hooks = {
    Stop = [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = "${claudeNotify}/bin/claude-notify";
          }
        ];
      }
    ];
  };
  mcpServers = {
    slack = {
      command = "npx";
      args = [
        "-y"
        "@modelcontextprotocol/server-slack"
      ];
      env = {
        SLACK_BOT_TOKEN = "__SLACK_TOKEN_PLACEHOLDER__";
        SLACK_TEAM_ID = "";
      };
    };
    "animate-ui" = {
      command = "npx";
      args = [
        "shadcn@latest"
        "mcp"
      ];
    };
  }
  // privateMcpConfig.mcpServers;
}
