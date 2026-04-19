{
  pkgs,
  lib,
  profiles,
}:
{
  wrapper = import ./wrapper.nix { inherit pkgs lib profiles; };
}
