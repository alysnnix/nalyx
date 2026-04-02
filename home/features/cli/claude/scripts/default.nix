{ pkgs, lib }:

let
  notify = import ./notify.nix { inherit pkgs; };
  statusline = import ./statusline.nix { inherit pkgs lib; };
in
{
  claude-notify = notify;
  claude-statusline = statusline;
  wrapper = import ./wrapper.nix;
}
