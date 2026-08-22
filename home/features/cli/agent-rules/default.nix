{
  pkgs,
  lib,
  config,
  enableClaude ? true,
  enableGemini ? true,
  enableOpencode ? true,
  ...
}:

# One declarative source of global agent rules, deployed to every agent CLI
# installed here. `rules.nix` owns the content, this module owns placement.
#
# This lives outside `claude/` on purpose. The rules are not Claude Code's,
# they are the user's, and Claude Code is one of five consumers.
#
# Each tool reads a different path, and none of them read another's, so a rule
# that is not written to a tool's own path simply does not exist for that tool:
#
#   ~/.omp/agent/AGENTS.md          omp, `native` provider
#   ~/.omp/agent/RULES.md           omp, sticky always-apply channel
#   ~/.claude/CLAUDE.md             Claude Code, and omp's `claude` provider
#   ~/.codex/AGENTS.md              Codex CLI
#   ~/.gemini/GEMINI.md             Gemini CLI
#   ~/.config/opencode/AGENTS.md    opencode
#
# Why AGENTS.md as well as CLAUDE.md for omp: omp keeps exactly ONE user-level
# context file, and its `native` provider (priority 100) shadows the `claude`
# one (priority 80). With no AGENTS.md the CLAUDE.md wins by default, which
# works right up until something drops a file at the native path and silently
# shadows every global rule. Writing both with identical content makes the
# outcome deterministic either way.
#
# Codex is detected at activation instead of gated on a flag. It is installed
# from the private repo (llm-agents.nix), so the public repo cannot know
# whether this host has it, and a public flag pretending to know would be
# lying. PR #170 removed the public codex module and its `enableCodex` flag
# for that reason; re-adding one here would just resurrect it. A `command -v`
# probe is the only thing that actually knows.
#
# Every managed target is a real file, not a symlink into the store, because
# agents edit these paths at runtime and a read-only symlink breaks that. That
# is also what makes drift possible, so each target carries a sidecar hash of
# what was last deployed. A target that no longer matches its sidecar was
# edited outside Nix and is backed up before being overwritten, never silently
# discarded. Runtime edits meant to survive belong in CLAUDE.local.md, which
# this module creates once and then never touches.
let
  rules = import ./rules.nix { inherit lib; };

  home = config.home.homeDirectory;

  importAwareFile = pkgs.writeText "agent-rules-md" rules.globalMd;
  plainFile = pkgs.writeText "agent-rules-plain-md" rules.globalMdPlain;
  stickyFile = pkgs.writeText "agent-rules-sticky-md" rules.rulesMd;

  # Tools that expand an `@path` token, so they get the CLAUDE.local.md import.
  importAwareTargets = [
    "${home}/.omp/agent/AGENTS.md"
  ]
  ++ lib.optional enableClaude "${home}/.claude/CLAUDE.md";

  # Tools that take the markdown verbatim.
  plainTargets =
    lib.optional enableGemini "${home}/.gemini/GEMINI.md"
    ++ lib.optional enableOpencode "${home}/.config/opencode/AGENTS.md";

  stickyTargets = [ "${home}/.omp/agent/RULES.md" ];

  deployLines =
    src: targets: lib.concatMapStringsSep "\n" (t: ''deploy_managed "${src}" "${t}"'') targets;
in
{
  home.activation.agentRules = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        PATH="${pkgs.coreutils}/bin:$PATH"

        deploy_managed() {
          src="$1"
          target="$2"
          sidecar="$(dirname "$target")/.$(basename "$target").nix-sha256"

          mkdir -p "$(dirname "$target")"

          # A symlink here is a leftover from the old home.file approach.
          if [ -L "$target" ]; then
            rm "$target"
          fi

          new_hash="$(sha256sum < "$src" | cut -d' ' -f1)"

          if [ -f "$target" ]; then
            cur_hash="$(sha256sum < "$target" | cut -d' ' -f1)"

            if [ "$cur_hash" = "$new_hash" ]; then
              # Already correct. Do not rewrite: some of these paths are synced
              # across hosts, and a needless mtime bump is needless sync churn.
              printf '%s\n' "$new_hash" > "$sidecar"
              return 0
            fi

            if [ -f "$sidecar" ] && [ "$cur_hash" != "$(cat "$sidecar")" ]; then
              backup="$target.drifted-$(date +%Y%m%d%H%M%S)"
              cp "$target" "$backup"
              echo "warning: $target was edited outside nix, saved to $backup" >&2
              echo "warning: durable rules belong in the nalyx repo under home/features/cli/agent-rules/, session-local ones in ~/.claude/CLAUDE.local.md" >&2
            fi
          fi

          cp "$src" "$target"
          chmod 644 "$target"
          printf '%s\n' "$new_hash" > "$sidecar"
        }

        ${deployLines "${importAwareFile}" importAwareTargets}
        ${deployLines "${plainFile}" plainTargets}
        ${deployLines "${stickyFile}" stickyTargets}

        if command -v codex > /dev/null 2>&1; then
          deploy_managed "${plainFile}" "${home}/.codex/AGENTS.md"
        fi

        # Unmanaged escape hatch, pulled in by the `@` import in the long form.
        # Created empty once so the import resolves; never rewritten after that.
        local_md="${home}/.claude/CLAUDE.local.md"
        if [ ! -e "$local_md" ]; then
          cat > "$local_md" <<'EOF'
    <!--
    Host-local or session-added guidance. Nix never overwrites this file.
    Imported by ~/.claude/CLAUDE.md and ~/.omp/agent/AGENTS.md, so anything here
    applies to every Claude Code and omp session on this host.

    Rules that should reach every host and every agent CLI belong in the nalyx
    repo instead, under home/features/cli/agent-rules/sections/.
    -->
    EOF
          chmod 644 "$local_md"
        fi
  '';
}
