{
  pkgs,
  lib,
  claudeSettingsBase,
}:

# Generate settings.json at activation time.
# Merges managed keys (plugins, mcpServers) into existing settings
# so Claude Code can write its own keys (effort, etc.) without being overwritten.
# Only generates for personal config — profiles symlink to it.
# Secret injection (MCPs, tokens) is handled by the private repo.
lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  JQ="${pkgs.jq}/bin/jq"

  CONFIG_DIR="$HOME/.claude"
  SETTINGS_FILE="$CONFIG_DIR/settings.json"

  mkdir -p "$CONFIG_DIR"

  # Remove symlink from previous home-manager generation if it exists
  if [ -L "$SETTINGS_FILE" ]; then
    rm "$SETTINGS_FILE"
  fi

  MANAGED=$(echo ${lib.escapeShellArg claudeSettingsBase})

  # Merge: existing settings * managed settings (managed keys win)
  if [ -f "$SETTINGS_FILE" ]; then
    EXISTING=$(cat "$SETTINGS_FILE")
    echo "$EXISTING" | $JQ --argjson managed "$MANAGED" '. * $managed' > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  else
    echo "$MANAGED" > "$SETTINGS_FILE"
  fi
''
