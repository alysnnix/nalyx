# Work wrapper — uses a separate config directory for the work account.
# Used when --work flag is passed.
''
  _claude_work() {
    (
      export CLAUDE_CONFIG_DIR="$HOME/.claude/accounts/work"
      command claude "$@"
    )
  }
''
