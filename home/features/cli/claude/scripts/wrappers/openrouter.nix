# OpenRouter modifier — sets env vars for OpenRouter API provider.
''
  local key_file="/run/secrets/openrouter_api_key"
  if [ ! -f "$key_file" ]; then
    echo "OpenRouter API key not found. Is sops configured?"
    return 1
  fi
  local openrouter_token
  openrouter_token="$(cat "$key_file")"
  extra_env+=("ANTHROPIC_BASE_URL=https://openrouter.ai/api")
  extra_env+=("ANTHROPIC_AUTH_TOKEN=$openrouter_token")
''
