{
  pkgs,
  lib,
  hasPrivate ? false,
  private ? null,
  ...
}:

let
  profiles = import ../claude/profiles.nix;

  scripts = import ./scripts { inherit pkgs lib profiles; };

  settings = import ./settings { inherit hasPrivate private; };

  activationSettings = import ./activation/settings.nix {
    inherit pkgs lib;
    inherit (settings) privateMcpConfig opencodeSettingsBase;
  };
in
{
  programs.zsh.initContent = scripts.wrapper;

  home = {
    packages = [
      pkgs.opencode
    ];

    activation.opencodeSettings = activationSettings;
  };
}
