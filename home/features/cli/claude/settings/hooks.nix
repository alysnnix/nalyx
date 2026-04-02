{ claude-notify }:
{
  hooksConfig = {
    Stop = [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = "claude-notify";
          }
        ];
      }
    ];
  };
}
