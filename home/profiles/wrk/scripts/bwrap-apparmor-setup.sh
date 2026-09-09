#!/usr/bin/env bash
set -euo pipefail

# Ubuntu 24.04+ enforces kernel.apparmor_restrict_unprivileged_userns=1: an
# unconfined process may no longer create a user namespace unless a loaded
# AppArmor profile grants it. Ubuntu ships that grant for exactly one path,
# /usr/bin/bwrap (see /etc/apparmor.d/bwrap-userns-restrict).
#
# packages/composio-cli.nix wraps the composio CLI in pkgs.buildFHSEnv, which
# is itself implemented on top of bwrap, at a /nix/store/<hash>/bin/bwrap path
# the shipped profile does not match. Without a matching profile, anything
# that resolves to that FHS wrapper (composio, nordvpn, any future
# buildFHSEnv package) fails with:
#   bwrap: setting up uid map: Permission denied
#
# The fix is the same grant, retargeted with a wildcard so it survives every
# nixpkgs bump instead of pinning today's store hash.

PROFILE=/etc/apparmor.d/nix-bwrap

if ! command -v apparmor_parser >/dev/null 2>&1; then
  echo "apparmor_parser not found, this host does not enforce the restriction, nothing to do"
  exit 0
fi

sudo tee "$PROFILE" >/dev/null <<'EOF'
# Mirrors /etc/apparmor.d/bwrap-userns-restrict, retargeted at bwrap binaries
# built by Nix instead of the one apt installs at /usr/bin/bwrap. See
# home/profiles/wrk/scripts/bwrap-apparmor-setup.sh for why this exists.
abi <abi/5.0>,
include <tunables/global>

profile nix-bwrap /nix/store/*/bin/bwrap flags=(attach_disconnected,mediate_deleted) {
  allow capability,
  allow file rwlkm /{**,},
  allow network,
  allow unix,
  allow ptrace,
  allow signal,
  allow mqueue,
  allow io_uring,
  allow userns,
  allow mount,
  allow umount,
  allow pivot_root,
  allow dbus,
  allow pix /** -> &nix-bwrap//&unpriv_bwrap,
}
EOF

sudo apparmor_parser -r "$PROFILE"
echo "loaded $PROFILE"
