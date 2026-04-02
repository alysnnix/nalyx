{
  hasPrivate ? false,
  private ? null,
  claude-statusline,
  claude-notify,
}:
let
  plugins = import ./plugins.nix;
  mcp-servers = import ./mcp-servers.nix { inherit hasPrivate private; };
  statusline = import ./statusline.nix { inherit claude-statusline; };
  hooks = import ./hooks.nix { inherit claude-notify; };
in
{
  claudeSettingsBase = builtins.toJSON {
    enabledPlugins = plugins.enabledPlugins;
    statusLine = statusline.statusLineConfig;
    hooks = hooks.hooksConfig;
    mcpServers = mcp-servers.publicMcpServers // mcp-servers.privateMcpConfig.mcpServers;
  };

  inherit (mcp-servers) privateMcpConfig;
}
