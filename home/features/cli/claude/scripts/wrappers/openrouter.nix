# OpenRouter wrapper — sets OpenRouter API environment variables.
# Used when --openrouter flag is passed.
''
  _claude_openrouter() {
    local key_file="/run/secrets/openrouter_api_key"

    if [ ! -f "$key_file" ]; then
      echo "OpenRouter API key not found. Is sops configured?"
      return 1
    fi

    local openrouter_token
    openrouter_token="$(cat "$key_file")"
    (
      export ANTHROPIC_BASE_URL="https://openrouter.ai/api/v1"
      export ANTHROPIC_AUTH_TOKEN="$openrouter_token"
      command claude "$@"
    )
  }
''
