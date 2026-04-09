{
  pkgs,
  lib,
  privateMcpConfig,
  claudeSettingsBase,
}:

# Generate settings.json at activation time with sops secret
# Merges managed keys (plugins, mcpServers) into existing settings
# so Claude Code can write its own keys (effort, etc.) without being overwritten
# Runs for both personal (~/.claude) and work (~/.claude-work) configs
lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  ANYTYPE_SECRET="/run/secrets/anytype_api_token"
  SLACK_SECRET="/run/secrets/slack_bot_token"
  JQ="${pkgs.jq}/bin/jq"

  for CONFIG_DIR in "$HOME/.claude" "$HOME/.claude/accounts/work"; do
    SETTINGS_FILE="$CONFIG_DIR/settings.json"

    mkdir -p "$CONFIG_DIR"

    # Remove symlink from previous home-manager generation if it exists
    if [ -L "$SETTINGS_FILE" ]; then
      rm "$SETTINGS_FILE"
    fi

    MANAGED=$(echo ${lib.escapeShellArg claudeSettingsBase})

    # Inject Anytype token or remove MCP entry
    if [ -f "$ANYTYPE_SECRET" ]; then
      TOKEN=$(cat "$ANYTYPE_SECRET")
      HEADERS=$($JQ -c -n \
        --arg token "$TOKEN" \
        '{"Authorization": ("Bearer " + $token), "Anytype-Version": "2025-11-08"}')
      MANAGED=$(echo "$MANAGED" | \
        $JQ --arg headers "$HEADERS" \
        '.mcpServers.anytype.env.OPENAPI_MCP_HEADERS = $headers')
    else
      MANAGED=$(echo "$MANAGED" | $JQ 'del(.mcpServers.anytype)')
    fi

    # Inject Slack token or remove MCP entry
    if [ -f "$SLACK_SECRET" ]; then
      SLACK_TOKEN=$(cat "$SLACK_SECRET")
      MANAGED=$(echo "$MANAGED" | \
        $JQ --arg token "$SLACK_TOKEN" \
        '.mcpServers.slack.env.SLACK_BOT_TOKEN = $token')
    else
      MANAGED=$(echo "$MANAGED" | $JQ 'del(.mcpServers.slack)')
    fi

    # Inject private MCP tokens (sapron, seazone, etc.) from nalyx-private
    ${privateMcpConfig.injectScript}

    # Merge: existing settings * managed settings (managed keys win)
    if [ -f "$SETTINGS_FILE" ]; then
      EXISTING=$(cat "$SETTINGS_FILE")
      echo "$EXISTING" | $JQ --argjson managed "$MANAGED" '. * $managed' > "$SETTINGS_FILE.tmp"
      mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    else
      echo "$MANAGED" > "$SETTINGS_FILE"
    fi
  done
''
