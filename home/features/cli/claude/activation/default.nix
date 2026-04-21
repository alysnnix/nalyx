{
  pkgs,
  lib,
  profiles,
  claudeSettingsBase,
  privateMcpConfig,
  claudeSkillsSrc,
}:

{
  claudeGlobalMd = import ./global-claude-md.nix { inherit lib; };

  claudeSkills = import ./skills.nix {
    inherit pkgs lib claudeSkillsSrc;
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
