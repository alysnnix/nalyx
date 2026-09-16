# Gearhub and the CLIs it fronts: ddcutil/ddcui for the AOC monitors over
# DDC/CI. The Corsair side talks to the OpenLinkHub daemon
# (modules/services/openlinkhub.nix) over HTTP, so nothing extra is needed
# here. Runs as a user service on 127.0.0.1:8686.
{ pkgs, ... }:
let
  gearhub = pkgs.callPackage ../../../../packages/gearhub { };
in
{
  home.packages = with pkgs; [
    ddcutil
    ddcui
    gearhub
  ];

  systemd.user.services.gearhub = {
    Unit = {
      Description = "Gearhub peripheral dashboard (loopback)";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${gearhub}/bin/gearhub --listen 127.0.0.1:8686";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
