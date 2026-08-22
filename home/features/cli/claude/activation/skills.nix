{
  pkgs,
  lib,
  claudeSkillsSrc,
}:

# Copy skills as real files so config dirs stay fully writeable.
# (home.file creates read-only symlinks that break marketplace/plugins)
# Only copies to personal config, profiles symlink to it.
lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  SKILLS_DST="$HOME/.claude/skills"
  mkdir -p "$SKILLS_DST"

  # Remove old symlinks from previous home.file approach
  ${pkgs.findutils}/bin/find "$SKILLS_DST" -type l -lname '*/nix/store/*' -delete 2>/dev/null || true

  # Remove stale directories from a legacy layout that predates the
  # .nix-managed marker used below. This list is frozen: every entry here
  # was renamed before the marker existed, so it had to be named by hand.
  # Any skill renamed from now on is pruned automatically by the marker
  # based step further down, so this list never needs a new entry.
  for old_dir in "$SKILLS_DST"/global "$SKILLS_DST"/impeccable "$SKILLS_DST"/generate-claude-doc "$SKILLS_DST"/gb-check-alfred-review "$SKILLS_DST"/global-*; do
    [ -d "$old_dir" ] && rm -rf "$old_dir"
  done

  # Copy managed skills as real writeable files
  cp -rL --no-preserve=mode "${claudeSkillsSrc}/." "$SKILLS_DST/"

  # Prune skills Nix used to manage but no longer does (e.g. after a rename).
  # Every managed skill directory carries a `.nix-managed` marker, dropped by
  # the claudeSkillsSrc derivation, so only directories that both carry the
  # marker and are absent from the current manifest get removed. Unmanaged
  # skills the user keeps by hand (no marker) and symlinks (like the
  # composio-cli plugin link) are never touched, and no name needs to be
  # listed here for this to work.
  for dir in "$SKILLS_DST"/*; do
    [ -L "$dir" ] && continue
    [ -d "$dir" ] || continue
    [ -e "$dir/.nix-managed" ] || continue
    name="$(basename "$dir")"
    [ -e "${claudeSkillsSrc}/$name/.nix-managed" ] && continue
    rm -rf "$dir"
  done
''
