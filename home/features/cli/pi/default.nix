{ pkgs, ... }:

# pi (https://pi.dev), a minimal multi-provider coding agent. Installed from
# the same llm-agents.nix input as Claude Code and omp, through the overlay in
# flake.nix.
#
# Anthropic auth is borrowed from Claude Code instead of logged in a second
# time. pi resolves the anthropic provider from $ANTHROPIC_OAUTH_TOKEN before
# it consults its own ~/.pi/agent/auth.json, so the zsh wrapper re-exports the
# OAuth token Claude Code keeps in ~/.claude/.credentials.json on every call.
# Whatever owns Claude Code's login then owns pi's login too: a plain `claude`
# login on a personal host, or a project layer that rotates the token behind
# Claude Code's back on a work one. One credential store, nothing to fall out
# of step. omp is wired the same way where that layer is present.
#
# Read at each invocation, never baked in at activation: the token refreshes
# independently of a rebuild, so an activation-time value would go stale. With
# no token pi runs untouched and its own `/login` still works.
#
# Rules land in ~/.pi/agent/AGENTS.md via agent-rules; skills are read from
# ~/.agents/skills, which agent-skills already writes, so nothing to link.
{
  home.packages = [ pkgs.pi ];

  programs.zsh.initContent = ''
    pi() {
      local creds="$HOME/.claude/.credentials.json"
      local token=""
      if [ -f "$creds" ]; then
        token=$(${pkgs.jq}/bin/jq -r '.claudeAiOauth.accessToken // empty' "$creds")
      fi
      if [ -n "$token" ]; then
        ANTHROPIC_OAUTH_TOKEN="$token" command pi "$@"
      else
        command pi "$@"
      fi
    }
  '';
}
