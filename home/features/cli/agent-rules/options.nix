{ lib, ... }:
# Declared apart from default.nix for the reason git/options.nix gives: a
# module with an `options` section has to move every config attribute under
# `config`, and restructuring the whole feature for one option is a worse trade.
{
  options.modules.cli.agentRules.extraDocs = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.strMatching "[a-z0-9-]+";
            example = "project-pr-validation";
            description = "File name under ~/.config/agent-rules/, without `.md`.";
          };
          title = lib.mkOption {
            type = lib.types.str;
            description = "Heading of the deployed doc.";
          };
          readWhen = lib.mkOption {
            type = lib.types.str;
            description = "The situation that sends an agent to read it, shown in the on-demand table.";
          };
          body = lib.mkOption {
            type = lib.types.lines;
            description = "Markdown body, deployed below the title.";
          };
        };
      }
    );
    default = [ ];
    description = ''
      On-demand docs appended to the global agent rules, beside the ones in
      sections/. Each one gets a row in the on-demand table of every agent
      CLI's context file and never a sticky line, so a layer can add guidance
      without adding per-turn context.

      Exists so a private project layer can ship rules scoped to that
      project's repos without the project's name reaching this public repo.
    '';
  };
}
