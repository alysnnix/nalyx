# Profile definitions for separate Claude accounts.
# Each profile gets its own config dir (~/.claude/accounts/<name>)
# with shared settings/skills symlinked from the personal config.
#
# Adding a new profile:
#   1. Add an entry here
#   2. Run `switch` to regenerate (creates dir, symlinks, wrapper flag)
#   3. Log in with `claude --<name>` on first use
{
  sec = { };
}
