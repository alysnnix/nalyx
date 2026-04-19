{
  hasPrivate ? false,
  private ? null,
}:
let
  providers = import ./providers.nix;
  mcp-servers = import ./mcp-servers.nix { inherit hasPrivate private; };
in
{
  opencodeSettingsBase = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    provider = providers.providers;
    model = providers.model;
    mcp = mcp-servers.publicMcpServers // mcp-servers.privateMcpConfig.mcpServers;
  };

  inherit (mcp-servers) privateMcpConfig;
}
