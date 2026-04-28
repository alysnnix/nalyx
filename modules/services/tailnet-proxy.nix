# Tailnet reverse proxy — exposes local services on the tailnet via HTTPS.
#
# Pipeline:
#   tailscale serve (:443 TLS) → nginx (127.0.0.1:18080) → backend services
#
# Nginx sits in the path because `tailscale serve` is a path-mount only and
# cannot redirect bare /service → /service/, nor route the root WebSocket of
# an SPA that hardcodes `wss://host/` to a specific backend.
#
# To add a service, append an entry to `services` below.
# Fields:
#   name           — informational, used for nginx vhost log clarity
#   path           — public subpath (no trailing slash). Example: "/openclaw"
#   target         — host:port of the local backend (loopback)
#   rootWebSocket  — optional, default false. When true, nginx routes WS
#                    upgrades on `/` to this service (for SPAs that hardcode
#                    their WebSocket URL to the root). At most ONE service
#                    may set this — the root path is a finite resource.
{
  pkgs,
  lib,
  ...
}:
let
  services = [
    {
      name = "openclaw";
      path = "/openclaw";
      target = "127.0.0.1:18789";
      rootWebSocket = true;
    }
  ];

  nginxPort = 18080;

  rootWsService = lib.findFirst (s: s.rootWebSocket or false) null services;

  serviceLocations = lib.listToAttrs (
    map (svc: {
      name = "${svc.path}/";
      value = {
        proxyPass = "http://${svc.target}/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 1d;
          proxy_send_timeout 1d;
        '';
      };
    }) services
  );

  # Special-case `/` for SPAs whose WebSocket is hardcoded to root.
  # Plain HTTP GETs on `/` get a 302 to the dashboard subpath; WS upgrades
  # are proxied to the claiming backend.
  rootLocation = lib.optionalAttrs (rootWsService != null) {
    "= /" = {
      proxyPass = "http://${rootWsService.target}";
      proxyWebsockets = true;
      extraConfig = ''
        if ($http_upgrade = "") {
          return 302 ${rootWsService.path}/;
        }
        proxy_read_timeout 1d;
      '';
    };
  };
in
{
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;

    virtualHosts.tailnet-proxy = {
      listen = [
        {
          addr = "127.0.0.1";
          port = nginxPort;
        }
      ];
      locations = serviceLocations // rootLocation;
    };
  };

  systemd.services.tailscale-serve-routes = {
    description = "Tailscale Serve → nginx reverse proxy";
    after = [
      "tailscaled.service"
      "nginx.service"
      "network-online.target"
    ];
    requires = [ "tailscaled.service" ];
    wants = [
      "nginx.service"
      "network-online.target"
    ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "30s";
    };

    script = ''
      ${pkgs.tailscale}/bin/tailscale serve reset || true
      echo "Forwarding tailnet HTTPS → nginx (127.0.0.1:${toString nginxPort})"
      ${pkgs.tailscale}/bin/tailscale serve --bg http://127.0.0.1:${toString nginxPort}
      echo "Done."
    '';
  };
}
