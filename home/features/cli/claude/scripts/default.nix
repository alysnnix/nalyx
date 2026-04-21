{
  pkgs,
  lib,
  profiles,
}:

let
  notify = import ./notify.nix { inherit pkgs; };
  statusline = import ./statusline.nix { inherit pkgs lib; };
  validatePr = import ./validate-pr.nix { inherit pkgs; };
in
{
  claude-notify = notify;
  claude-statusline = statusline;
  claude-validate-pr = validatePr;
  wrapper = import ./wrappers/default.nix { inherit pkgs lib profiles; };
}
