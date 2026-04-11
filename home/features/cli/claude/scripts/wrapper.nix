# Re-exports the full wrapper initContent from wrappers/default.nix.
{
  pkgs,
  lib,
  profiles,
}:
import ./wrappers/default.nix { inherit pkgs lib profiles; }
