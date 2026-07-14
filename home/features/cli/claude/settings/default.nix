{
  claude-statusline,
  claude-notify,
  claude-validate-pr,
}:
let
  plugins = import ./plugins.nix;
  mcp-servers = import ./mcp-servers.nix;
  statusline = import ./statusline.nix { inherit claude-statusline; };
  hooks = import ./hooks.nix { inherit claude-notify claude-validate-pr; };
in
{
  claudeSettingsBase = builtins.toJSON {
    copyOnSelect = false;
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    inherit (plugins) enabledPlugins;
    statusLine = statusline.statusLineConfig;
    hooks = hooks.hooksConfig;
    mcpServers = mcp-servers.publicMcpServers;
  };
}
