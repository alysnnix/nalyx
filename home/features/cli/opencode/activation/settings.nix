{
  pkgs,
  lib,
  privateMcpConfig,
  opencodeSettingsBase,
}:

lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  ANYTYPE_SECRET="/run/secrets/anytype_api_token"
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

  # Inject Claude Code OAuth token into opencode auth.json (enables built-in anthropic provider)
  CC_CREDS="$HOME/.claude/.credentials.json"
  OC_AUTH_DIR="$HOME/.local/share/opencode"
  OC_AUTH_FILE="$OC_AUTH_DIR/auth.json"
  if [ -f "$CC_CREDS" ]; then
    CC_TOKEN=$($JQ -r '.claudeAiOauth.accessToken // empty' "$CC_CREDS")
    if [ -n "$CC_TOKEN" ]; then
      mkdir -p "$OC_AUTH_DIR"
      if [ -f "$OC_AUTH_FILE" ]; then
        $JQ --arg key "$CC_TOKEN" '.anthropic = {"type": "api", "key": $key}' \
          "$OC_AUTH_FILE" > "$OC_AUTH_FILE.tmp" && mv "$OC_AUTH_FILE.tmp" "$OC_AUTH_FILE"
      else
        echo '{}' | $JQ --arg key "$CC_TOKEN" '.anthropic = {"type": "api", "key": $key}' > "$OC_AUTH_FILE"
      fi
    fi
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
