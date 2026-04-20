{
  hasPrivate ? false,
  private ? null,
  claude-statusline,
  claude-notify,
  claude-validate-pr,
}:
let
  plugins = import ./plugins.nix;
  mcp-servers = import ./mcp-servers.nix { inherit hasPrivate private; };
  statusline = import ./statusline.nix { inherit claude-statusline; };
  hooks = import ./hooks.nix { inherit claude-notify claude-validate-pr; };
in
{
  claudeSettingsBase = builtins.toJSON {
    copyOnSelect = false;
    enabledPlugins = plugins.enabledPlugins;
    statusLine = statusline.statusLineConfig;
    hooks = hooks.hooksConfig;
    mcpServers = mcp-servers.publicMcpServers // mcp-servers.privateMcpConfig.mcpServers;
  };

  inherit (mcp-servers) privateMcpConfig;
}
