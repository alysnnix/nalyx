{
  pkgs,
  lib,
  ...
}:

let
  profiles = import ./profiles.nix;

  scripts = import ./scripts { inherit pkgs lib profiles; };

  skills = import ./skills/files.nix { inherit pkgs lib; };

  # The rules are the user's, not Claude Code's, so the source lives in the
  # agent-rules feature and this is one of its consumers.
  agent-sticky-rules = import ../agent-rules/sticky-hook.nix { inherit pkgs lib; };

  settings = import ./settings {
    inherit (scripts) claude-statusline claude-notify claude-validate-pr;
    inherit agent-sticky-rules;
  };

  activation = import ./activation {
    inherit
      pkgs
      lib
      profiles
      ;
    inherit (settings) claudeSettingsBase;
    inherit (skills) claudeSkillsSrc;
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

    activation = {
      inherit (activation)
        claudeSkills
        claudeSettings
        claudeProfiles
        ;
    };
  };
}
