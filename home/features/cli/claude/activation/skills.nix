{
  pkgs,
  lib,
  claudeSkillsSrc,
}:

# Copy skills as real files so config dirs stay fully writeable
# (home.file creates read-only symlinks that break marketplace/plugins)
# Runs for both personal (~/.claude) and work (~/.claude-work) configs
lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  for CONFIG_DIR in "$HOME/.claude" "$HOME/.claude/accounts/work"; do
    SKILLS_DST="$CONFIG_DIR/skills"
    mkdir -p "$SKILLS_DST"

    # Remove old symlinks from previous home.file approach
    ${pkgs.findutils}/bin/find "$SKILLS_DST" -type l -lname '*/nix/store/*' -delete 2>/dev/null || true

    # Remove stale directories from previous naming schemes
    for old_dir in "$SKILLS_DST"/global "$SKILLS_DST"/impeccable "$SKILLS_DST"/generate-claude-doc; do
      [ -d "$old_dir" ] && rm -rf "$old_dir"
    done

    # Copy managed skills as real writeable files
    cp -rL --no-preserve=mode "${claudeSkillsSrc}/." "$SKILLS_DST/"
  done
''
