# Claude Code modifier — uses OAuth token from Claude Code subscription.
# Writes the access token to opencode's auth.json for the built-in anthropic provider.
# Token expires ~60 days after login; re-login with `claude` to refresh.
{ pkgs }:
let
  jq = "${pkgs.jq}/bin/jq";
in
''
  local creds_file="$HOME/.claude/.credentials.json"
  if [ ! -f "$creds_file" ]; then
    echo "Claude Code credentials not found. Run 'claude' to log in first."
    return 1
  fi
  local cc_token
  cc_token=$(${jq} -r '.claudeAiOauth.accessToken // empty' "$creds_file")
  if [ -z "$cc_token" ]; then
    echo "No OAuth token found in Claude Code credentials. Run 'claude' to log in."
    return 1
  fi

  # Write token to opencode's auth.json for the built-in anthropic provider
  local auth_dir="$HOME/.local/share/opencode"
  local auth_file="$auth_dir/auth.json"
  mkdir -p "$auth_dir"

  # Merge with existing auth.json (preserve other providers)
  if [ -f "$auth_file" ]; then
    ${jq} --arg key "$cc_token" \
      '.anthropic = {"type": "api", "key": $key}' \
      "$auth_file" > "$auth_file.tmp" && mv "$auth_file.tmp" "$auth_file"
  else
    echo '{}' | ${jq} --arg key "$cc_token" \
      '.anthropic = {"type": "api", "key": $key}' > "$auth_file"
  fi
''
