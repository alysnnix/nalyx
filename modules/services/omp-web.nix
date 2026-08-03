# omp-web: browse and continue your omp chats from any tailnet device.
#
# Topology (tailnet-only, nothing on the LAN or public internet):
#   tailscale serve (:443 TLS, tailnet) → nginx (127.0.0.1) → omp-web (127.0.0.1)
#
# nginx sits in the path purely for reliable WebSocket upgrades (the streaming
# "continue" channel), mirroring the tailnet-proxy module. The service runs as
# the user so the spawned `omp --mode rpc` sees ~/.omp auth and the project cwd.
#
# Access is gated by Google OIDC (email allowlist). The client id/secret and the
# allowed email are read from ~/.config/omp-web.env (0600, NOT in git) — see the
# EnvironmentFile below. Missing file => auth fails closed (nobody gets in).
{
  lib,
  pkgs,
  vars,
  ...
}:
let
  user = vars.user.name;
  port = 8790; # omp-web loopback
  nginxPort = 18082; # nginx loopback (distinct from tailnet-proxy's 18080)
  ompWeb = pkgs.callPackage ../../packages/omp-web { };
in
{
  systemd.services.omp-web = {
    description = "omp-web: browse and continue omp sessions";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      OMP_WEB_HOST = "127.0.0.1";
      OMP_WEB_PORT = toString port;
      HOME = "/home/${user}";
      OMP_WEB_AUTH = "google";
    };
    serviceConfig = {
      ExecStart = lib.getExe ompWeb;
      User = user;
      Restart = "on-failure";
      RestartSec = "5s";
      # Google OIDC creds + allowed email come from a SOPS secret in the
      # private repo, decrypted here at activation. Optional ("-") so the unit
      # still starts if absent; auth then fails closed (nobody gets in).
      EnvironmentFile = "-/run/secrets/omp_web_env";
    };
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts.omp-web = {
      listen = [
        {
          addr = "127.0.0.1";
          port = nginxPort;
        }
      ];
      # Mounted at root: SPA, REST and the /api/stream WebSocket all share one
      # origin, so a single proxy location handles everything (no path rewrite).
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 1d;
          proxy_send_timeout 1d;
        '';
      };
    };
  };

  systemd.services.omp-web-tailscale-serve = {
    description = "Tailscale Serve → omp-web (nginx)";
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

    script = ''
      # On a cold boot tailscaled is still settling; wait until it is Running.
      for _ in $(seq 1 60); do
        ${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
          | grep -q '"BackendState": *"Running"' && break
        sleep 1
      done
      ${pkgs.tailscale}/bin/tailscale serve reset || true
      echo "Serving omp-web on the tailnet (HTTPS → nginx 127.0.0.1:${toString nginxPort})"
      ${pkgs.tailscale}/bin/tailscale serve --bg http://127.0.0.1:${toString nginxPort}
    '';
  };
}
