{ claude-notify, claude-validate-pr }:
{
  hooksConfig = {
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
