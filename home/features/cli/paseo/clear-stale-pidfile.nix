{ pkgs }:
# Removes a paseo.pid left behind by a daemon that did not shut down cleanly.
#
# paseo-server refuses to start while $PASEO_HOME/paseo.pid names a live PID,
# and it only checks that the PID exists, not that it is still a Paseo. After a
# reboot (on WSL, every `wsl --shutdown`) the old lock survives and low PIDs get
# handed out again in a similar order, so the stored PID often belongs to some
# other early service (syncthing, once). The daemon then exits with "Another
# Paseo daemon is already running" and the unit restart-loops forever.
#
# The lock is kept only when its PID is alive and its cmdline mentions Paseo
# (the running daemon retitles itself "Paseo Supervisor"), so a real second
# daemon started by hand still blocks the unit, as it should.
pkgs.writeShellApplication {
  name = "paseo-clear-stale-pidfile";
  runtimeInputs = [
    pkgs.jq
    pkgs.gnugrep
    pkgs.coreutils
  ];
  text = ''
    pidfile="''${PASEO_HOME:?PASEO_HOME is not set}/paseo.pid"
    [ -e "$pidfile" ] || exit 0

    pid=$(jq -r '.pid // empty' "$pidfile" 2>/dev/null || true)
    if [ -n "$pid" ] && grep -qai paseo "/proc/$pid/cmdline" 2>/dev/null; then
      exit 0
    fi

    echo "removing stale $pidfile (pid ''${pid:-unknown} is not a Paseo daemon)"
    rm -f "$pidfile"
  '';
}
