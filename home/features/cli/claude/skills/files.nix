{ pkgs, lib }:

# Skills managed by nix: destination (relative to ~/.claude/skills/) -> source
# Impeccable skills are managed as a plugin (impeccable@pbakaus) via enabledPlugins
let
  skillFiles = {
    "gb-devcontainer/SKILL.md" = ./global/devcontainer/SKILL.md;
    "gb-generate-claude-doc/SKILL.md" = ./global/generate-claude-doc/SKILL.md;
    "gb-open-pr/SKILL.md" = ./global/open-pr/SKILL.md;
    "gb-review-prs/SKILL.md" = ./global/review-prs/SKILL.md;
    "gb-check-review/SKILL.md" = ./global/check-review/SKILL.md;
    "gb-merge-dev/SKILL.md" = ./global/merge-dev/SKILL.md;
    "gb-co-authored/SKILL.md" = ./global/co-authored/SKILL.md;

    # Templates - Stack specific rules
    "gb-generate-claude-doc/templates/stack/testing-vitest/rules/testing.md" =
      ./global/generate-claude-doc/templates/stack/testing-vitest/rules/testing.md;
    "gb-generate-claude-doc/templates/stack/typescript/rules/typescript.md" =
      ./global/generate-claude-doc/templates/stack/typescript/rules/typescript.md;

    # Templates - Universal
    "gb-generate-claude-doc/templates/universal/rules/quality.md" =
      ./global/generate-claude-doc/templates/universal/rules/quality.md;
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
