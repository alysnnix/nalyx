# Blanks the panel when the lid closes on AC power.
#
# logind keeps the machine awake there (HandleLidSwitchExternalPower=ignore in
# /etc/systemd/logind.conf.d/lid.conf), but with no external monitor mutter
# leaves the closed panel lit. On battery logind suspends first, so the AC
# check only matters for the lid closing in the moment the cable comes out.
#
# The session is locked before blanking: a lid close used to mean a suspend,
# which locks, and this must not leave an open session behind a closed lid.

display_power() {
  busctl --user set-property org.gnome.Mutter.DisplayConfig \
    /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig \
    PowerSaveMode i "$1"
}

on_battery() {
  [ "$(busctl get-property org.freedesktop.UPower /org/freedesktop/UPower \
    org.freedesktop.UPower OnBattery)" = "b true" ]
}

gdbus monitor --system --dest org.freedesktop.UPower \
  --object-path /org/freedesktop/UPower |
  while read -r line; do
    case "$line" in
    *"'LidIsClosed': <true>"*)
      on_battery && continue
      gdbus call --session --dest org.gnome.ScreenSaver \
        --object-path /org/gnome/ScreenSaver \
        --method org.gnome.ScreenSaver.Lock >/dev/null
      display_power 3
      ;;
    *"'LidIsClosed': <false>"*)
      display_power 0
      ;;
    esac
  done
