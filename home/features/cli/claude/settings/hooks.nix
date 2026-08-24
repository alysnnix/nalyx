{
  claude-notify,
  claude-validate-pr,
  agent-sticky-rules,
}:
{
  hooksConfig = {
    # Re-attaches the sticky rules on every prompt. Claude Code reads
    # CLAUDE.md once at session start, so without this the rules fade as the
    # opening context scrolls out of attention.
    UserPromptSubmit = [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = "${agent-sticky-rules}/bin/agent-sticky-rules";
          }
        ];
      }
    ];
    PreToolUse = [
      {
        matcher = "Bash";
        hooks = [
          {
            type = "command";
            command = "${claude-validate-pr}/bin/claude-validate-pr";
          }
        ];
      }
    ];
    Stop = [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = "${claude-notify}/bin/claude-notify";
          }
        ];
      }
    ];
  };
}
