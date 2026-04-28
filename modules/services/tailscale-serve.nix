# Tailscale Serve reverse proxy — exposes local services on the tailnet via HTTPS.
# Add routes below to expose new services. Each entry maps a URL path to a local target.
#
# Usage:
#   https://homelab.<tailnet>.ts.net/openclaw → http://localhost:18789
#
# To add a new service, append to the `routes` list:
#   { path = "/grafana"; target = "http://localhost:3000"; }
{
  pkgs,
  ...
}:
let
  routes = [
    {
      path = "/openclaw";
      target = "http://localhost:18789";
    }
  ];

  routeCommands = builtins.concatStringsSep "\n" (
    map (r: ''
      echo "  ${r.path} → ${r.target}"
      ${pkgs.tailscale}/bin/tailscale serve --bg --set-path ${r.path} ${r.target}
    '') routes
  );
in
{
  systemd.services.tailscale-serve-routes = {
    description = "Tailscale Serve routes";
    after = [
      "tailscaled.service"
      "network-online.target"
    ];
    requires = [ "tailscaled.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "30s";
    };

    script = ''
      ${pkgs.tailscale}/bin/tailscale serve reset || true
      echo "Configuring Tailscale Serve routes..."
      ${routeCommands}
      echo "Routes configured."
    '';
  };
}
