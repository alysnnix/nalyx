# Tailnet reverse proxy — exposes local services on the tailnet via HTTPS.
#
# Pipeline:
#   tailscale serve (:443 TLS) → nginx (127.0.0.1:18080) → backend services
#
# Nginx sits in the path because `tailscale serve` is a path-mount only and
# does not handle WebSocket upgrades on bare-prefix paths reliably.
#
# Each service gets two nginx locations:
#   - `= /<path>`  exact match, proxied without rewrite. WebSocket clients
#                  hit this when the SPA derives its gateway URL as
#                  `wss://host/<path>` (no trailing slash). A 301 here
#                  would break the upgrade because browsers do not follow
#                  redirects on WS handshakes (causes wsclose 1006).
#   - `/<path>/`  prefix match, proxied with path stripped. Serves the SPA
#                  HTML and any sub-paths.
#
# To add a service, append an entry to `services` below.
# Fields:
#   name    — informational, used for nginx vhost log clarity
#   path    — public subpath (no trailing slash). Example: "/openclaw"
#   target  — host:port of the local backend (loopback)
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
    }
  ];

  nginxPort = 18080;

  proxyExtraConfig = ''
    proxy_read_timeout 1d;
    proxy_send_timeout 1d;
  '';

  serviceLocations = lib.listToAttrs (
    lib.concatMap (svc: [
      {
        name = "= ${svc.path}";
        value = {
          proxyPass = "http://${svc.target}";
          proxyWebsockets = true;
          extraConfig = proxyExtraConfig;
        };
      }
      {
        name = "${svc.path}/";
        value = {
          proxyPass = "http://${svc.target}/";
          proxyWebsockets = true;
          extraConfig = proxyExtraConfig;
        };
      }
    ]) services
  );

  # Bare `/` redirects to the first service's dashboard.
  defaultPath = (builtins.head services).path;
  rootLocation = {
    "= /" = {
      return = "302 ${defaultPath}/";
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
