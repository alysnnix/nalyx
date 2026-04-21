{
  pkgs,
  lib,
  hasPrivate ? false,
  private ? null,
  ...
}:

let
  settings = import ./settings { inherit hasPrivate private; };

  activationSettings = import ./activation/settings.nix {
    inherit pkgs lib;
    inherit (settings) privateMcpConfig opencodeSettingsBase;
  };
in
{
  home = {
    packages = [
      pkgs.opencode
    ];

    activation.opencodeSettings = activationSettings;
  };
}
