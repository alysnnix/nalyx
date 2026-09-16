# OpenLinkHub: daemon for the Corsair iCUE LINK TITAN 360 RX (pump, fans and
# the LCD on the pump head). Serves its own web UI and REST API on
# 127.0.0.1:27003, which gearhub proxies under /openlinkhub/.
#
# The nixpkgs package installs the app and its assets read-only under
# $pkg/opt/OpenLinkHub, but the daemon writes its config and device database
# into its working directory. So the unit runs from /var/lib/openlinkhub
# (StateDirectory) and seeds the writable copies from the store on first start.
#
# Hardware access comes from the package's udev rules (chown the Corsair USB
# nodes to the "openlinkhub" user), so the service runs as that dedicated user
# instead of root.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.modules.services.openlinkhub;
  seed = pkgs.writeShellScript "openlinkhub-seed" ''
    # Copy the writable trees out of the store only when missing, so user
    # edits (device profiles, dashboard settings) survive restarts and
    # package updates.
    for dir in database static web; do
      if [ ! -e "/var/lib/openlinkhub/$dir" ]; then
        cp -r --no-preserve=mode \
          "${pkgs.openlinkhub}/opt/OpenLinkHub/$dir" /var/lib/openlinkhub/
      fi
    done
  '';
in
{
  options.modules.services.openlinkhub.enable =
    lib.mkEnableOption "OpenLinkHub daemon for Corsair iCUE LINK devices";

  config = lib.mkIf cfg.enable {
    services.udev.packages = [ pkgs.openlinkhub ];

    users.users.openlinkhub = {
      isSystemUser = true;
      group = "openlinkhub";
    };
    users.groups.openlinkhub = { };

    systemd.services.openlinkhub = {
      description = "OpenLinkHub daemon (web UI + REST on 127.0.0.1:27003)";
      after = [ "systemd-udev-settle.service" ];
      wants = [ "systemd-udev-settle.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        User = "openlinkhub";
        Group = "openlinkhub";
        # "input" for the uinput node its udev rules expose, "i2c" for the
        # pump LCD path; the USB hidraw nodes are chowned to the user by the
        # package's own rules.
        SupplementaryGroups = [
          "input"
          "i2c"
        ];
        StateDirectory = "openlinkhub";
        WorkingDirectory = "/var/lib/openlinkhub";
        ExecStartPre = seed;
        ExecStart = lib.getExe' pkgs.openlinkhub "OpenLinkHub";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
