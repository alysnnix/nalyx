{
  pkgs,
  lib,
  enableClaude ? true,
  ...
}:

# Third-party agent skills, deployed to `~/.agents/skills`.
#
# This lives outside `claude/` for the same reason agent-rules does: the skills
# are not Claude Code's, and Claude Code is one of several consumers.
#
# `~/.agents/skills` is the agent-agnostic location, and the agents disagree on
# whether they read it:
#
#   ~/.agents/skills    omp (`agents` provider, priority 70), Codex CLI
#   ~/.claude/skills    Claude Code, which scans only its own directory
#
# So omp and Codex pick the directory up unaided and Claude Code is the only
# consumer needing an explicit link. Codex is not gated on a flag here for the
# reason agent-rules spells out: it comes from the private repo, so the public
# repo cannot know whether a host has it. Nothing needs to know either, since
# writing the directory is enough for Codex to find it.
#
# omp de-duplicates skills by realpath, so a skill reachable through both the
# `agents` and `claude` providers is still listed once rather than colliding.
#
# Files are copied real and writeable instead of symlinked into the store, the
# same call the Claude skills make: `skills add` / `skills update` rewrite these
# directories in place, and a read-only store symlink breaks that.
let
  inherit (import ./sources.nix { inherit pkgs lib; }) agentSkillsSrc;

  copyManaged = ''
    SKILLS_DST="$HOME/.agents/skills"
    mkdir -p "$SKILLS_DST"

    cp -rL --no-preserve=mode "${agentSkillsSrc}/." "$SKILLS_DST/"

    # Prune skills Nix used to manage but no longer does, e.g. after a rename.
    # Same `.nix-managed` marker contract as the Claude skills: a directory is
    # removed only when it carries the marker AND is absent from the current
    # manifest, so skills installed by hand with `npx skills add` (composio-cli)
    # carry no marker and are never touched.
    for dir in "$SKILLS_DST"/*; do
      [ -L "$dir" ] && continue
      [ -d "$dir" ] || continue
      [ -e "$dir/.nix-managed" ] || continue
      [ -e "${agentSkillsSrc}/$(basename "$dir")/.nix-managed" ] && continue
      rm -rf "$dir"
    done
  '';

  # Relative link target so it never matches the `*/nix/store/*` sweep the
  # Claude skills activation runs, which would otherwise delete these on the
  # next switch. That sweep also skips symlinks when pruning, so the two
  # activation entries are order-independent.
  linkIntoClaude = ''
    CLAUDE_DST="$HOME/.claude/skills"
    mkdir -p "$CLAUDE_DST"

    for dir in "${agentSkillsSrc}"/*; do
      name="$(basename "$dir")"
      ln -sfn "../../.agents/skills/$name" "$CLAUDE_DST/$name"
    done
  '';
in
{
  home.activation.agentSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    copyManaged + lib.optionalString enableClaude linkIntoClaude
  );
}
