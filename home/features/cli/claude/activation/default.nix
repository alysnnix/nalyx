{
  pkgs,
  lib,
  hasPrivate ? false,
  private ? null,
  profiles,
  claudeStatusline ? null,
  claudeNotify ? null,
  ...
}@args:

let
  mcpServersModule = import ../settings/mcp-servers.nix { inherit hasPrivate private; };
  privateMcpConfig = mcpServersModule.privateMcpConfig;

  claudeSettingsBaseModule = import ../settings/claude-settings-base.nix {
    inherit lib privateMcpConfig;
    inherit claudeStatusline claudeNotify;
  };
  claudeSettingsBase = claudeSettingsBaseModule;

  skillsFiles = import ../skills/files.nix { inherit pkgs lib; };
in
{
  claudeGlobalMd = import ./global-claude-md.nix { inherit lib; };

  claudeSkills = import ./skills.nix {
    inherit pkgs lib;
    claudeSkillsSrc = skillsFiles.claudeSkillsSrc;
  };

  claudeSettings = import ./settings.nix {
    inherit
      pkgs
      lib
      privateMcpConfig
      claudeSettingsBase
      ;
  };

  claudeProfiles = import ./profiles.nix {
    inherit pkgs lib profiles;
  };
}
