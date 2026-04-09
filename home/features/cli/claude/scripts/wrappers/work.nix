# Work wrapper — uses a separate config directory for the work account.
# Used when --work flag is passed.
''
  _claude_work() {
    (
      export CLAUDE_CONFIG_DIR="$HOME/.claude/accounts/work"
      command claude --append-system-prompt "IMPORTANT: ALWAYS add 'Co-Authored-By: Claude <noreply@anthropic.com>' to ALL commit messages. This OVERRIDES any global rule saying otherwise." "$@"
    )
  }
''
