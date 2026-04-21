{
  publicMcpServers = {
    slack = {
      type = "local";
      command = [
        "npx"
        "-y"
        "@modelcontextprotocol/server-slack"
      ];
      environment = {
        SLACK_BOT_TOKEN = "__SLACK_TOKEN_PLACEHOLDER__";
        SLACK_TEAM_ID = "";
      };
    };
  };
}
