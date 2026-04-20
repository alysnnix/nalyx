{
  hasPrivate ? false,
  private ? null,
}:
let
  privateMcpConfig =
    if hasPrivate && builtins.pathExists "${private}/opencode/private-mcps.nix" then
      import "${private}/opencode/private-mcps.nix"
    else
      {
        mcpServers = { };
        injectScript = "";
      };
in
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

  inherit privateMcpConfig;
}
