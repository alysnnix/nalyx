{
  pkgs,
  lib,
  claudeSettingsBase,
}:

# Generate settings.json at activation time with sops secrets.
# Merges managed keys (plugins, mcpServers) into existing settings
# so Claude Code can write its own keys (effort, etc.) without being overwritten.
# Only generates for personal config — profiles symlink to it.
lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  SLACK_SECRET="/run/secrets/slack_bot_token"
  JQ="${pkgs.jq}/bin/jq"

  CONFIG_DIR="$HOME/.claude"
  SETTINGS_FILE="$CONFIG_DIR/settings.json"

  mkdir -p "$CONFIG_DIR"

  # Remove symlink from previous home-manager generation if it exists
  if [ -L "$SETTINGS_FILE" ]; then
    rm "$SETTINGS_FILE"
  fi

  MANAGED=$(echo ${lib.escapeShellArg claudeSettingsBase})

  # Inject Slack token or remove MCP entry
  if [ -f "$SLACK_SECRET" ]; then
    SLACK_TOKEN=$(cat "$SLACK_SECRET")
    MANAGED=$(echo "$MANAGED" | \
      $JQ --arg token "$SLACK_TOKEN" \
      '.mcpServers.slack.env.SLACK_BOT_TOKEN = $token')
  else
    MANAGED=$(echo "$MANAGED" | $JQ 'del(.mcpServers.slack)')
  fi

  # Merge: existing settings * managed settings (managed keys win)
  if [ -f "$SETTINGS_FILE" ]; then
    EXISTING=$(cat "$SETTINGS_FILE")
    echo "$EXISTING" | $JQ --argjson managed "$MANAGED" '. * $managed' > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  else
    echo "$MANAGED" > "$SETTINGS_FILE"
  fi
''
