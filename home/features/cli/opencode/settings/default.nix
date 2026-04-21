let
  providers = import ./providers.nix;
  mcp-servers = import ./mcp-servers.nix;
in
{
  opencodeSettingsBase = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    provider = providers.providers;
    inherit (providers) model;
    mcp = mcp-servers.publicMcpServers;
  };
}
