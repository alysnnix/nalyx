# English feedback wrapper — enables CLAUDE_ENGLISH_FEEDBACK.
# Used when --english flag is passed without --minimax.
''
  _claude_english() {
    (
      export CLAUDE_ENGLISH_FEEDBACK=1
      command claude "''${remaining_args[@]}"
    )
  }
''
