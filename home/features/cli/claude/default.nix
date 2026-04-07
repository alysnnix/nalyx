{
  pkgs,
  lib,
  hasPrivate ? false,
  private ? null,
  ...
}:

let
  # Scripts: notify sound, statusline formatter, and shell wrappers
  scripts = import ./scripts { inherit pkgs lib; };

  # Skills: file mapping and derivation builder
  skills = import ./skills/files.nix { inherit pkgs lib; };

  # Settings: plugins, MCP servers, statusline, hooks
  settings = import ./settings {
    inherit hasPrivate private;
    claude-statusline = scripts.claude-statusline;
    claude-notify = scripts.claude-notify;
    claude-validate-pr = scripts.claude-validate-pr;
  };

  # Activation snippets: copy skills and generate settings.json
  activation = import ./activation {
    inherit
      pkgs
      lib
      hasPrivate
      private
      ;
    claudeStatusline = scripts.claude-statusline;
    claudeNotify = scripts.claude-notify;
    claudeSkillsSrc = skills.claudeSkillsSrc;
  };
in
{
  programs.zsh.initContent = scripts.wrapper;

  home = {
    sessionVariables = {
      CLAUDE_CODE_NO_FLICKER = "1";
    };

    packages = [
      pkgs.claude-code
      scripts.claude-notify
    ];

    activation.claudeSkills = activation.claudeSkills;
    activation.claudeSettings = activation.claudeSettings;
  };
}
