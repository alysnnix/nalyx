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
#
# `switch` runs this on every non-NixOS activation, so the checks below all
# exist to reach "nothing to do" without ever calling sudo: a password prompt
# on every rebuild would be worse than the bug this fixes.

PROFILE=/etc/apparmor.d/nix-bwrap

WANT=$(
  cat <<'EOF'
# Mirrors /etc/apparmor.d/bwrap-userns-restrict, retargeted at bwrap binaries
# built by Nix instead of the one apt installs at /usr/bin/bwrap. See
# home/profiles/wrk/scripts/bwrap-apparmor-setup.sh for why this exists.
#
# Managed by `switch`. Local edits are overwritten on the next activation.
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
)

# No AppArmor tooling: a distro that does not mediate this at all, so bwrap is
# already free to unshare and there is nothing to grant.
if ! command -v apparmor_parser >/dev/null 2>&1; then
  echo "  apparmor: not installed, nothing to do"
  exit 0
fi

# The restriction can be off (older Ubuntu, or a host that turned the sysctl
# off deliberately). Loading the profile would be harmless but pointless, and
# it would cost a sudo prompt, so skip. A missing knob reads as 0 for the same
# reason: no restriction, no grant needed.
RESTRICTED=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)
if [ "$RESTRICTED" != "1" ]; then
  echo "  apparmor: userns restriction is off, nothing to do"
  exit 0
fi

# The common path: already installed and unchanged. Compared against the file
# rather than against `aa-status`, which would itself need root; AppArmor loads
# everything under /etc/apparmor.d at boot, so a matching file means a loaded
# profile on any host that has rebooted since.
if [ -f "$PROFILE" ] && [ "$(cat "$PROFILE")" = "$WANT" ]; then
  exit 0
fi

echo "  apparmor: installing $PROFILE (needs sudo)"
printf '%s\n' "$WANT" | sudo tee "$PROFILE" >/dev/null
sudo apparmor_parser -r "$PROFILE"
echo "  apparmor: loaded $PROFILE"
