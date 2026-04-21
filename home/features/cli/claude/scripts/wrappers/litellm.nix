# LiteLLM modifier — sets env vars for LiteLLM proxy provider.
''
  local key_file="/run/secrets/litellm_api_key"
  if [ ! -f "$key_file" ]; then
    echo "LiteLLM API key not found. Is sops configured?"
    return 1
  fi
  local litellm_token
  litellm_token="$(cat "$key_file")"
  extra_env+=("ANTHROPIC_BASE_URL=https://hub.seazone.dev/v1")
  extra_env+=("ANTHROPIC_AUTH_TOKEN=$litellm_token")
''
