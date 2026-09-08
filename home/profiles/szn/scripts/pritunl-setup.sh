#!/usr/bin/env bash
set -euo pipefail

# Installs the Pritunl daemon as a SYSTEM unit, which home-manager cannot do:
# pritunl-client-service creates tun devices and rewrites the routing table, so
# it needs root, and a systemd --user unit has neither privilege nor the right
# lifetime. The nix package already ships the unit, with the absolute store
# path of pritunl-client-service baked into ExecStart.
#
# The unit is symlinked out of the home-manager profile rather than copied, so
# it tracks the profile: a copy would keep pointing at a store path that the
# next garbage collection removes, and the daemon would then fail to start with
# nothing in the logs to suggest why. Re-run this after a switch that bumps
# pritunl to pick up the new ExecStart.

UNIT_SRC="$HOME/.nix-profile/lib/systemd/system/pritunl-client.service"
UNIT_DST="/etc/systemd/system/pritunl-client.service"

if [ ! -e "$UNIT_SRC" ]; then
  echo "error: $UNIT_SRC not found" >&2
  echo "  the pritunl-client package is not in the profile yet; run 'switch szn'" >&2
  exit 1
fi

# On a managed laptop IT may well have installed pritunl from their own .deb,
# in which case a real unit file already owns this name. Clobbering it would
# silently take over a service someone else is responsible for, so stop and let
# a human decide which of the two should win.
if [ -e "$UNIT_DST" ] && [ ! -L "$UNIT_DST" ]; then
  echo "error: $UNIT_DST already exists and is a real file, not our symlink" >&2
  echo "  something else (most likely an apt-installed pritunl) owns this unit." >&2
  echo "  pick one: remove that package, or drop pritunl-client from the szn profile." >&2
  exit 1
fi

echo "linking $UNIT_DST -> $UNIT_SRC"
sudo ln -sfn "$UNIT_SRC" "$UNIT_DST"
sudo systemctl daemon-reload
sudo systemctl enable pritunl-client
sudo systemctl restart pritunl-client

echo
systemctl --no-pager --lines=0 status pritunl-client
