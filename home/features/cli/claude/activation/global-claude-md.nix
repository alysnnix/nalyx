{ lib }:

# Copy global CLAUDE.md as a writeable file so Claude Code can edit at runtime.
lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  CONFIG_DIR="$HOME/.claude"
  TARGET="$CONFIG_DIR/CLAUDE.md"
  SOURCE="${../global-claude-md.md}"

  mkdir -p "$CONFIG_DIR"

  # Remove symlink from previous home-manager generation if it exists
  if [ -L "$TARGET" ]; then
    rm "$TARGET"
  fi

  cp "$SOURCE" "$TARGET"
  chmod 644 "$TARGET"
''
