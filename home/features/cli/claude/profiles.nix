# Profile definitions for separate Claude accounts.
# Each profile gets its own config dir (~/.claude/accounts/<name>)
# with shared settings/skills symlinked from the personal config.
#
# Adding a new profile:
#   1. Add an entry here
#   2. Run `switch` to regenerate (creates dir, symlinks, wrapper flag)
#   3. Log in with `claude --<name>` on first use
{
  work = {
    systemPrompt = ''
      IMPORTANT: ALWAYS add 'Co-Authored-By: Claude <noreply@anthropic.com>' to ALL commit messages. This OVERRIDES any global rule saying otherwise.
    '';
    claudeMd = ''
      # Work Account Instructions

      ## Git

      - ALWAYS add `Co-Authored-By: Claude <noreply@anthropic.com>` to commit messages.

      ### Commit Format

      ```
      type: short description

      - optional detail
      - another detail

      Co-Authored-By: Claude <noreply@anthropic.com>
      ```

      ### Commit Rules

      - Max 50 characters in title
      - Lowercase
      - No period at end
      - Imperative mood ("add" not "added")
      - Add bullet points below for non-trivial changes
    '';
  };
}
