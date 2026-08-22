{
  pkgs,
  lib,
  profiles,
  claudeSettingsBase,
  claudeSkillsSrc,
}:

{

  claudeSkills = import ./skills.nix {
    inherit pkgs lib claudeSkillsSrc;
  };

  claudeSettings = import ./settings.nix {
    inherit
      pkgs
      lib
      claudeSettingsBase
      ;
  };

  claudeProfiles = import ./profiles.nix {
    inherit pkgs lib profiles;
  };
}
