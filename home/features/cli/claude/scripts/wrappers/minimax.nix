# Minimax modifier — sets env vars for MiniMax API provider.
''
  local key_file="/run/secrets/minimax_api_key"
  if [ ! -f "$key_file" ]; then
    echo "MiniMax API key not found. Is sops configured?"
    return 1
  fi
  local minimax_token
  minimax_token="$(cat "$key_file")"
  extra_env+=("ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic")
  extra_env+=("ANTHROPIC_AUTH_TOKEN=$minimax_token")
  extra_env+=("ANTHROPIC_MODEL=MiniMax-M2.7")
  extra_env+=("ANTHROPIC_SMALL_FAST_MODEL=MiniMax-M2.7")
''
