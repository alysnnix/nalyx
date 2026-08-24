{ pkgs, lib }:

# Gives Claude Code the sticky-rule channel it does not have natively.
#
# omp loads RULES.md as an always-apply rule and re-attaches it near the
# current turn, so a sticky rule keeps its hold deep into a long session.
# Claude Code has no equivalent: CLAUDE.md is read once at the top of the
# session and then scrolls out of attention along with the rest of the
# opening context. A rule that only lives there is a rule that fades.
#
# `UserPromptSubmit` closes that gap. Its `additionalContext` is prepended
# to the user's message before the model sees it, on every turn, which is
# the same re-attachment behaviour by a different mechanism.
#
# This emits the whole sticky bundle rather than one hand-picked rule. That
# is both less code (rules.nix already renders it) and self-maintaining: a
# `sticky` line added to any section reaches Claude Code with no edit here.
#
# The JSON is built by Nix and written to the store, so the script is a
# single `cat` of a static file. Assembling it in shell would mean escaping
# the backticks, quotes and newlines the rule text carries, and this hook
# runs on every single prompt, so it has no business doing work at runtime.
let
  rules = import ./rules.nix { inherit lib; };

  # Framed so the model does not read the injection as something the user
  # typed in the current message.
  context = ''
    <standing-rules>
    Re-attached on every turn from the user's global agent rules. Not part of the current message, and in force for the whole session.

    ${rules.rulesMd}
    </standing-rules>
  '';

  payload = pkgs.writeText "agent-sticky-rules.json" (
    builtins.toJSON {
      hookSpecificOutput = {
        hookEventName = "UserPromptSubmit";
        additionalContext = context;
      };
    }
  );
in
pkgs.writeShellScriptBin "agent-sticky-rules" ''
  exec ${pkgs.coreutils}/bin/cat ${payload}
''
