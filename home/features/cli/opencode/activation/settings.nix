{
  pkgs,
  lib,
  opencodeSettingsBase,
}:

# Generate opencode.jsonc at activation time.
# Merges managed keys (provider, mcp) into existing settings.
# Secret injection (API keys, tokens, MCPs) is handled by the private repo.
lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  JQ="${pkgs.jq}/bin/jq"

  CONFIG_DIR="$HOME/.config/opencode"
  SETTINGS_FILE="$CONFIG_DIR/opencode.jsonc"

  mkdir -p "$CONFIG_DIR"

  # Remove symlink from previous home-manager generation if it exists
  if [ -L "$SETTINGS_FILE" ]; then
    rm "$SETTINGS_FILE"
  fi

  MANAGED=$(echo ${lib.escapeShellArg opencodeSettingsBase})

  # Merge: existing settings * managed settings (managed keys win)
  if [ -f "$SETTINGS_FILE" ]; then
    EXISTING=$(cat "$SETTINGS_FILE")
    echo "$EXISTING" | $JQ --argjson managed "$MANAGED" '. * $managed' > "$SETTINGS_FILE.tmp"
    mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  else
    echo "$MANAGED" > "$SETTINGS_FILE"
  fi
''
