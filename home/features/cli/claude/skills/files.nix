{ pkgs, lib }:

# Skills managed by nix: destination (relative to ~/.claude/skills/) -> source
# Impeccable skills are managed as a plugin (impeccable@pbakaus) via enabledPlugins
let
  skillFiles = {
    "gb-open-pr/SKILL.md" = ./global/open-pr/SKILL.md;
    "gb-check-alfred-review/SKILL.md" = ./global/check-review/SKILL.md;
    "gb-merge-dev/SKILL.md" = ./global/merge-dev/SKILL.md;
    "gb-co-authored/SKILL.md" = ./global/co-authored/SKILL.md;
    "gb-pipefy/SKILL.md" = ./global/pipefy/SKILL.md;
  };

  # Build a derivation with all skill files collected in one directory tree
  claudeSkillsSrc = pkgs.runCommandLocal "claude-skills" { } (
    "mkdir -p $out\n"
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (dest: src: ''
        mkdir -p "$out/$(dirname '${dest}')"
        cp '${src}' "$out/${dest}"
      '') skillFiles
    )
  );
in
{
  inherit skillFiles claudeSkillsSrc;
}
