{
  pkgs,
  lib,
  ...
}:

let
  profiles = import ./profiles.nix;

  scripts = import ./scripts { inherit pkgs lib profiles; };

  skills = import ./skills/files.nix { inherit pkgs lib; };

  settings = import ./settings {
    inherit (scripts) claude-statusline claude-notify claude-validate-pr;
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
      # Disable Claude Code mouse handling so it stops opening links on click
      # (terminal handles link clicks alone, avoiding double-open). Trade-off:
      # no wheel scroll inside the TUI.
      CLAUDE_CODE_DISABLE_MOUSE = "1";
    };

    packages = [
      pkgs.claude-code
      (pkgs.writeShellScriptBin "claude-prev" ''exec ${pkgs.claude-code-prev}/bin/claude "$@"'')
      scripts.claude-notify
    ];

    activation = {
      inherit (activation)
        claudeGlobalMd
        claudeSkills
        claudeSettings
        claudeProfiles
        ;
    };
  };
}
