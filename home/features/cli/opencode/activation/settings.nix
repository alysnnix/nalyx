{
  pkgs,
  lib,
  privateMcpConfig,
  opencodeSettingsBase,
}:

lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  SLACK_SECRET="/run/secrets/slack_bot_token"
  LITELLM_SECRET="/run/secrets/litellm_api_key"
  JQ="${pkgs.jq}/bin/jq"

  CONFIG_DIR="$HOME/.config/opencode"
  SETTINGS_FILE="$CONFIG_DIR/opencode.jsonc"

  mkdir -p "$CONFIG_DIR"

  # Remove symlink from previous home-manager generation if it exists
  if [ -L "$SETTINGS_FILE" ]; then
    rm "$SETTINGS_FILE"
  fi

  MANAGED=$(echo ${lib.escapeShellArg opencodeSettingsBase})

  # Inject LiteLLM API key or remove provider
  if [ -f "$LITELLM_SECRET" ]; then
    LLM_KEY=$(cat "$LITELLM_SECRET")
    MANAGED=$(echo "$MANAGED" | \
      $JQ --arg key "$LLM_KEY" \
      '.provider.litellm.options.apiKey = $key')
  else
    MANAGED=$(echo "$MANAGED" | $JQ 'del(.provider.litellm)')
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

  # Inject Claude Code OAuth token into claude-code provider or remove it
  CC_CREDS="$HOME/.claude/.credentials.json"
  if [ -f "$CC_CREDS" ]; then
    CC_TOKEN=$($JQ -r '.claudeAiOauth.accessToken // empty' "$CC_CREDS")
    if [ -n "$CC_TOKEN" ]; then
      MANAGED=$(echo "$MANAGED" | \
        $JQ --arg token "Bearer $CC_TOKEN" \
        '.provider."claude-code".options.headers.Authorization = $token')
    else
      MANAGED=$(echo "$MANAGED" | $JQ 'del(.provider."claude-code")')
    fi
  else
    MANAGED=$(echo "$MANAGED" | $JQ 'del(.provider."claude-code")')
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
