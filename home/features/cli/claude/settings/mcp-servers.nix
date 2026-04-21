{
  hasPrivate ? false,
  private ? null,
}:
let
  privateMcpConfig =
    if hasPrivate && builtins.pathExists "${private}/claude/private-mcps.nix" then
      import "${private}/claude/private-mcps.nix"
    else
      {
        mcpServers = { };
        injectScript = "";
      };
in
{
  publicMcpServers = {
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
  };

  inherit privateMcpConfig;
}
