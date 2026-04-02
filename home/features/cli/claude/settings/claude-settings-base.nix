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
    "figma@claude-plugins-official" = true;
    "firebase@claude-plugins-official" = true;
    "frontend-design@claude-plugins-official" = true;
    "impeccable@pbakaus" = true;
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
    command = "${claudeStatusline}";
  };
  hooks = {
    Stop = [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = "${claudeNotify}";
          }
        ];
      }
    ];
  };
  mcpServers = {
    anytype = {
      command = "npx";
      args = [
        "-y"
        "@anyproto/anytype-mcp"
      ];
      env = {
        OPENAPI_MCP_HEADERS = "__ANYTYPE_TOKEN_PLACEHOLDER__";
      };
    };
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
  }
  // privateMcpConfig.mcpServers;
}
