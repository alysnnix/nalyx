#!/usr/bin/env bash
set -euo pipefail

# Nothing creates /run/opengl-driver off NixOS, and that is the only place the
# nix libglvnd looks for its vendor ICD. Every nix-built GL app therefore dies
# before it opens a window, with an error that names no driver and no path:
#   Found no glutin configs matching the template ... NoGlutinConfigs
#
# home-manager's targets.genericLinux.gpu already builds the driver env and
# ships `non-nixos-gpu-setup`, which installs a systemd unit that makes the
# symlink. That needs root, so activation only prints a warning and the app
# keeps failing until someone reads it. `switch` runs this wrapper instead.
#
# Same shape as bwrap-apparmor-setup.sh: every check below exists to reach
# "nothing to do" without calling sudo, because a password prompt on each
# rebuild would be worse than the bug. The link also goes stale on any nixpkgs
# bump that moves mesa, and a stale link fails exactly like a missing one, so
# the comparison is against the current drivers path rather than mere presence.
# It is the same comparison home-manager's own activation check makes.

WANT="@drivers@"

# The setup helper comes from the same module that builds WANT, so its absence
# means the gpu integration is off (nixGL took over, or this is NixOS) and
# there is nothing here to install.
if ! command -v non-nixos-gpu-setup >/dev/null 2>&1; then
  echo "  gpu: non-nixos-gpu-setup not installed, nothing to do"
  exit 0
fi

CURRENT=$(readlink /run/opengl-driver 2>/dev/null || true)
if [ "$CURRENT" = "$WANT" ]; then
  exit 0
fi

if [ -z "$CURRENT" ]; then
  echo "  gpu: linking /run/opengl-driver at the nix drivers (needs sudo)"
else
  echo "  gpu: drivers moved, relinking /run/opengl-driver (needs sudo)"
fi

# Absolute path, because sudo resets PATH to secure_path and the nix profile is
# not on it.
sudo "$(command -v non-nixos-gpu-setup)"
echo "  gpu: /run/opengl-driver -> $(readlink /run/opengl-driver 2>/dev/null || echo unset)"
