{
  pkgs,
  lib,
  privateMcpConfig,
  opencodeSettingsBase,
}:

lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  ANYTYPE_SECRET="/run/secrets/anytype_api_token"
  SLACK_SECRET="/run/secrets/slack_bot_token"
  JQ="${pkgs.jq}/bin/jq"

  CONFIG_DIR="$HOME/.config/opencode"
  SETTINGS_FILE="$CONFIG_DIR/opencode.jsonc"

  mkdir -p "$CONFIG_DIR"

  # Remove symlink from previous home-manager generation if it exists
  if [ -L "$SETTINGS_FILE" ]; then
    rm "$SETTINGS_FILE"
  fi

  MANAGED=$(echo ${lib.escapeShellArg opencodeSettingsBase})

  # Inject Anytype token or remove MCP entry
  if [ -f "$ANYTYPE_SECRET" ]; then
    TOKEN=$(cat "$ANYTYPE_SECRET")
    HEADERS=$($JQ -c -n \
      --arg token "$TOKEN" \
      '{"Authorization": ("Bearer " + $token), "Anytype-Version": "2025-11-08"}')
    MANAGED=$(echo "$MANAGED" | \
      $JQ --arg headers "$HEADERS" \
      '.mcp.anytype.environment.OPENAPI_MCP_HEADERS = $headers')
  else
    MANAGED=$(echo "$MANAGED" | $JQ 'del(.mcp.anytype)')
  fi

  # Inject Slack token or remove MCP entry
  if [ -f "$SLACK_SECRET" ]; then
    SLACK_TOKEN=$(cat "$SLACK_SECRET")
    MANAGED=$(echo "$MANAGED" | \
      $JQ --arg token "$SLACK_TOKEN" \
      '.mcp.slack.environment.SLACK_BOT_TOKEN = $token')
  else
    MANAGED=$(echo "$MANAGED" | $JQ 'del(.mcp.slack)')
  fi

  # Inject private MCP tokens from nalyx-private
  ${privateMcpConfig.injectScript}

  # Merge: existing settings * managed settings (managed keys win)
  if [ -f "$SETTINGS_FILE" ]; then
    EXISTING=$(cat "$SETTINGS_FILE")
    echo "$EXISTING" | $JQ --argjson managed "$MANAGED" '. * $managed' > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  else
    echo "$MANAGED" > "$SETTINGS_FILE"
  fi
''
