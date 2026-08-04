# omp-collab: self-hosted relay + browser client for omp's `/collab` live
# session sharing, entirely on the tailnet, never touching the public
# my.omp.sh. Lets you continue a running omp session from your phone WITHOUT
# closing it on the host: the host keeps running the agent; guests read the
# live stream and can prompt / interrupt. Every payload is E2E AES-256-GCM
# sealed by the clients, so the relay (and this whole path) only sees ciphertext.
#
# Topology (the WSL's own tailscale node, tailnet-only):
#   tailscale serve (:443 TLS) → nginx (127.0.0.1:18084)
#       ├── /      → static collab-web guest client
#       └── /r/…   → collab relay (127.0.0.1:8792), WebSocket
#
# Wire the omp host at it with `collab.relayUrl` (see home/features/cli/omp).
{
  lib,
  pkgs,
  ...
}:
let
  relayPort = 8792; # relay loopback
  nginxPort = 18084; # nginx loopback
  servePort = 443; # tailnet HTTPS port
  ompCollab = pkgs.callPackage ../../packages/omp-collab { };
in
{
  systemd.services.omp-collab-relay = {
    description = "omp-collab: content-blind relay for /collab live sessions";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      OMP_COLLAB_HOST = "127.0.0.1";
      OMP_COLLAB_PORT = toString relayPort;
    };
    serviceConfig = {
      ExecStart = lib.getExe ompCollab.relay;
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts.omp-collab = {
      listen = [
        {
          addr = "127.0.0.1";
          port = nginxPort;
        }
      ];
      # Static guest client at the root; the relay's room WebSocket under /r/.
      locations."/" = {
        root = ompCollab.web;
        tryFiles = "$uri /index.html";
      };
      locations."/r/" = {
        proxyPass = "http://127.0.0.1:${toString relayPort}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 1d;
          proxy_send_timeout 1d;
        '';
      };
    };
  };

  systemd.services.omp-collab-tailscale-serve = {
    description = "Tailscale Serve → omp-collab (nginx)";
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
      TimeoutStartSec = "120s";
      Restart = "on-failure";
      RestartSec = "5s";
    };

    # Additive serve (no node-wide `serve reset`); preStop removes only this
    # port, leaving any other tailscale serve config intact.
    script = ''
      for _ in $(seq 1 60); do
        ${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
          | grep -q '"BackendState": *"Running"' && break
        sleep 1
      done
      echo "Serving omp-collab on the tailnet (HTTPS :${toString servePort} → nginx 127.0.0.1:${toString nginxPort})"
      ${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString servePort} http://127.0.0.1:${toString nginxPort}
    '';
    preStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString servePort} off || true";
  };
}
