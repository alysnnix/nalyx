{ pkgs }:

pkgs.writeShellScriptBin "claude-notify" ''
  if command -v powershell.exe &>/dev/null; then
    powershell.exe -Command "[console]::beep(330, 60); [console]::beep(250, 60); [console]::beep(330, 60); [console]::beep(250, 60); [console]::beep(440, 90); [console]::beep(520, 110)" &>/dev/null
  elif command -v paplay &>/dev/null; then
    paplay /usr/share/sounds/freedesktop/stereo/complete.oga &>/dev/null
  fi
  exit 0
''
