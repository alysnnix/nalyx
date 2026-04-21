{
  pkgs,
  lib,
  hasPrivate ? false,
  private ? null,
  ...
}:

let
  profiles = import ./profiles.nix;

  scripts = import ./scripts { inherit pkgs lib profiles; };

  skills = import ./skills/files.nix { inherit pkgs lib; };

  settings = import ./settings {
    inherit hasPrivate private;
    claude-statusline = scripts.claude-statusline;
    claude-notify = scripts.claude-notify;
    claude-validate-pr = scripts.claude-validate-pr;
  };

  activation = import ./activation {
    inherit
      pkgs
      lib
      profiles
      ;
    inherit (settings) claudeSettingsBase privateMcpConfig;
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

    activation.claudeGlobalMd = activation.claudeGlobalMd;
    activation.claudeSkills = activation.claudeSkills;
    activation.claudeSettings = activation.claudeSettings;
    activation.claudeProfiles = activation.claudeProfiles;
  };
}
