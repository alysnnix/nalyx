{
  pkgs,
  lib,
  ...
}:

let
  settings = import ./settings;

  activationSettings = import ./activation/settings.nix {
    inherit pkgs lib;
    inherit (settings) opencodeSettingsBase;
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
