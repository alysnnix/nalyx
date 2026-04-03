# Minimax wrapper — sets MiniMax API environment variables.
# Used when --minimax flag is passed.
''
  _claude_minimax() {
    local key_file="/run/secrets/minimax_api_key"

    if [ ! -f "$key_file" ]; then
      echo "MiniMax API key not found. Is sops configured?"
      return 1
    fi

    local minimax_token
    minimax_token="$(cat "$key_file")"
    (
      export ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic"
      export ANTHROPIC_AUTH_TOKEN="$minimax_token"
      export ANTHROPIC_MODEL="MiniMax-M2.7"
      export ANTHROPIC_SMALL_FAST_MODEL="MiniMax-M2.7"
      command claude "$@"
    )
  }
''
