{
  pkgs,
  lib,
  profiles,
}:

let
  profileActivations = lib.mapAttrsToList (
    name: profile:
    let
      hasClaudeMd = profile ? claudeMd && profile.claudeMd != null;
      hasSystemPrompt = profile ? systemPrompt && profile.systemPrompt != null;
      claudeMdFile = pkgs.writeText "claude-profile-${name}-md" (
        if hasClaudeMd then profile.claudeMd else ""
      );
      systemPromptFile = pkgs.writeText "claude-profile-${name}-prompt" (
        if hasSystemPrompt then profile.systemPrompt else ""
      );
    in
    ''
      PROFILE_DIR="$HOME/.claude/accounts/${name}"
      mkdir -p "$PROFILE_DIR"

      # Symlink shared files (settings, local overrides)
      for f in settings.json settings.local.json; do
        TARGET="$HOME/.claude/$f"
        LINK="$PROFILE_DIR/$f"
        if [ -f "$TARGET" ]; then
          [ -f "$LINK" ] && [ ! -L "$LINK" ] && rm "$LINK"
          [ ! -e "$LINK" ] && ln -sf "$TARGET" "$LINK"
        fi
      done

      # Symlink shared directories (skills, plugins)
      for d in skills plugins; do
        TARGET="$HOME/.claude/$d"
        LINK="$PROFILE_DIR/$d"
        if [ -d "$TARGET" ]; then
          [ -d "$LINK" ] && [ ! -L "$LINK" ] && rm -rf "$LINK"
          [ ! -e "$LINK" ] && ln -sf "$TARGET" "$LINK"
        fi
      done

      ${lib.optionalString hasClaudeMd ''
        cp "${claudeMdFile}" "$PROFILE_DIR/CLAUDE.md"
        chmod 644 "$PROFILE_DIR/CLAUDE.md"
      ''}
      ${lib.optionalString hasSystemPrompt ''
        cp "${systemPromptFile}" "$PROFILE_DIR/.system-prompt"
        chmod 644 "$PROFILE_DIR/.system-prompt"
      ''}
    ''
  ) profiles;
in
lib.hm.dag.entryAfter [ "claudeSettings" "claudeSkills" ] (
  lib.concatStringsSep "\n" profileActivations
)
