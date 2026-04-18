# Claude Code modifier — uses OAuth token from Claude Code subscription.
# Reads the access token from ~/.claude/.credentials.json (managed by claude login).
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
  extra_env+=("ANTHROPIC_AUTH_TOKEN=$cc_token")
''
