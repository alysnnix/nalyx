{ pkgs, lib }:

# Skills managed by nix: destination (relative to ~/.claude/skills/) -> source
# Impeccable skills are managed as a plugin (impeccable@pbakaus) via enabledPlugins
let
  skillFiles = {
    "global-devcontainer/SKILL.md" = ./global/devcontainer/SKILL.md;
    "global-generate-claude-doc/SKILL.md" = ./global/generate-claude-doc/SKILL.md;
    "global-git-workflow/SKILL.md" = ./global/git-workflow/SKILL.md;
    "global-open-pr/SKILL.md" = ./global/open-pr/SKILL.md;

    # Templates - Stack specific rules
    "global-generate-claude-doc/templates/stack/testing-vitest/rules/testing.md" =
      ./global/generate-claude-doc/templates/stack/testing-vitest/rules/testing.md;
    "global-generate-claude-doc/templates/stack/typescript/rules/typescript.md" =
      ./global/generate-claude-doc/templates/stack/typescript/rules/typescript.md;

    # Templates - Universal
    "global-generate-claude-doc/templates/universal/skills/git-workflow/SKILL.md" =
      ./global/generate-claude-doc/templates/universal/skills/git-workflow/SKILL.md;
    "global-generate-claude-doc/templates/universal/rules/quality.md" =
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
