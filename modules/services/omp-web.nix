# omp-web: browse and continue your omp chats from any tailnet device.
#
# Topology (Option A — tailnet-only, served by the WSL's own tailscale node;
# nothing on the LAN or public internet):
#   tailscale serve (:443 TLS, tailnet) → nginx (127.0.0.1) → omp-web (127.0.0.1)
#
# Requires the WSL tailscale node to be logged in once: `sudo tailscale up`
# (it is a separate node from the Windows Tailscale app; both coexist). nginx
# sits in the path for reliable WebSocket upgrades (the streaming "continue"
# channel), mirroring the tailnet-proxy module.
#
# The service runs as the user so `omp --mode rpc` sees ~/.omp auth and the
# project cwd. Google OIDC creds + allowed email + the public base URL come from
# a SOPS secret (/run/secrets/omp_web_env); missing => auth fails closed.
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
      # Google OIDC creds + allowed email + OMP_WEB_BASE_URL from a SOPS secret
      # in the private repo, decrypted at activation. Optional ("-") so the unit
      # still starts if absent; auth then fails closed.
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
      # Single service mounted at root: SPA, REST and the /api/stream WebSocket
      # all share one origin, so one proxy location handles everything.
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 1d;
          proxy_send_timeout 1d;
          # tailscale serve terminates TLS in front of nginx; tell the app the
          # public scheme is https so OAuth redirect URIs are correct.
          proxy_set_header X-Forwarded-Proto https;
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
