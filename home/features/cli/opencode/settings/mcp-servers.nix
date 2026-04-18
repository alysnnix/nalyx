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
    anytype = {
      type = "local";
      command = [
        "npx"
        "-y"
        "@anyproto/anytype-mcp"
      ];
      environment = {
        OPENAPI_MCP_HEADERS = "__ANYTYPE_TOKEN_PLACEHOLDER__";
      };
    };
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
